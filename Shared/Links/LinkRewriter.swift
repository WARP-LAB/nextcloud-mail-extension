import Foundation

/// Replaces linked files with their links where each file was (FR8), and adds the links to all files and the
/// password notice after the user's own text (FR7, FR9). See docs/ARCHITECTURE.md, "Rewriter".
///
/// Each alternative of a `multipart/alternative`, such as the plain text and the HTML, shows every linked file:
/// in place where Mail left a placeholder or the file's own part, and otherwise in a list after the user's own text.
struct LinkRewriter {
    var text = LinkText()

    /// Rewrites `message` in place and returns its bytes.
    ///
    /// - Parameter links: the links of each linked file, by `MessageFile.index`. Files without links stay.
    /// - Returns: the original bytes, unchanged, when there are no links, folder links or notice to add.
    func rewrite(_ message: MimeMessage, links: [Int: LinkedFile], folder: FolderLinks?, passwordNotice: Bool) -> Data {
        guard !links.isEmpty || folder != nil || passwordNotice else {
            return message.original
        }
        let rewriting = Rewriting(message: message, links: links, text: text, folder: folder, notice: passwordNotice)
        rewriting.run()
        return message.data()
    }
}

private final class Rewriting {
    /// The linked files a branch must show, and those it has placed.
    final class Branch {
        let shows: [Int]
        var placed = Set<Int>()

        init(shows: [Int]) {
            self.shows = shows
        }
    }

    let message: MimeMessage
    let files: [MessageFile]
    let links: [Int: LinkedFile]
    let text: LinkText
    let folder: FolderLinks?
    let notice: Bool
    private let indexOfPart: [ObjectIdentifier: Int]
    private let indexOfContentID: [String: Int]

    init(message: MimeMessage, links: [Int: LinkedFile], text: LinkText, folder: FolderLinks?, notice: Bool) {
        self.message = message
        self.links = links
        self.text = text
        self.folder = folder
        self.notice = notice
        files = message.files
        indexOfPart = Dictionary(uniqueKeysWithValues: files.map { (ObjectIdentifier($0.part), $0.index) })
        indexOfContentID = Dictionary(
            files.compactMap { file in file.contentID.map { ($0.lowercased(), file.index) } },
            uniquingKeysWith: { first, _ in first }
        )
    }

    var eol: String {
        message.eol
    }

    func run() {
        let root = message.root
        if let index = indexOfPart[ObjectIdentifier(root)], let link = links[index] {
            replaceRootFile(root, with: link)
            return
        }
        let branch = Branch(shows: linkedIndexes(in: root))
        let result = process(root, branch)
        if root.contentType != "multipart/alternative" {
            finish(branch, in: result)
        }
        if result !== root {
            adoptContent(of: result, into: root)
        }
    }

    // MARK: - Walking the parts

    /// Processes a part, and returns it or the part that replaces it.
    private func process(_ part: MimePart, _ branch: Branch) -> MimePart {
        if part.isMultipart {
            if part.contentType == "multipart/alternative" {
                let shows = linkedIndexes(in: part)
                part.children = part.children.map { child in
                    let alternative = Branch(shows: shows)
                    let result = process(child, alternative)
                    finish(alternative, in: result)
                    return result
                }
                return part
            }
            var children = part.children.map { process($0, branch) }
            let subtype = children.contains { $0.isText && $0.contentType == "text/html" } ? "html" : "plain"
            children = children.compactMap { child in
                guard child.isFile, let index = indexOfPart[ObjectIdentifier(child)], let link = links[index] else {
                    return child
                }
                // In multipart/mixed, the file's part is where the file was. Elsewhere, such as in
                // multipart/related, a file not placed by its placeholder goes in the list at the end.
                guard part.contentType == "multipart/mixed", !branch.placed.contains(index) else {
                    return nil
                }
                branch.placed.insert(index)
                return makeText(subtype, subtype == "html" ? text.html(link) : text.plain(link))
            }
            part.children = merged(children)
            return part.children.count == 1 ? part.children[0] : part
        }
        if part.isText, let content = part.text {
            let replaced =
                part.contentType == "text/html"
                ? replacingHTMLPlaceholders(in: content, branch) : replacingPlainPlaceholders(in: content, branch)
            if replaced != content {
                setText(part, replaced)
            }
        }
        return part
    }

    /// Replaces `<img src="cid:…">` and `<object data="cid:…">` of linked files with their links.
    private func replacingHTMLPlaceholders(in html: String, _ branch: Branch) -> String {
        let placeholder = #/<(img|object)\b[^>]*?(?:src|data)=["']cid:([^"']+)["'][^>]*>(?:\s*</object>)?/#
        return html.replacing(placeholder.ignoresCase()) { match in
            guard let index = indexOfContentID[String(match.2).lowercased()], let link = links[index] else {
                return String(match.0)
            }
            branch.placed.insert(index)
            return text.html(link)
        }
    }

    /// Replaces Mail's U+FFFC placeholders with links. They stand for the message's files in document order, so
    /// they're only used when there is one for each file.
    private func replacingPlainPlaceholders(in plain: String, _ branch: Branch) -> String {
        let placeholders = plain.filter { $0 == "\u{FFFC}" }.count
        guard placeholders > 0, placeholders == files.count else {
            return plain
        }
        var position = 0
        var output = ""
        for character in plain {
            guard character == "\u{FFFC}" else {
                output.append(character)
                continue
            }
            if let link = links[position] {
                branch.placed.insert(position)
                output += text.plain(link)
            } else {
                output.append(character)
            }
            position += 1
        }
        return output
    }

    // MARK: - Finishing a branch

    /// Adds the branch's unplaced files as a list, then the links to all files and the password notice, after the
    /// user's own text.
    private func finish(_ branch: Branch, in part: MimePart) {
        let unplaced = branch.shows.filter { !branch.placed.contains($0) }.compactMap { links[$0] }
        let htmlItems =
            unplaced.map { text.html($0) } + [text.html(folder: folder, passwordNotice: notice)].compactMap { $0 }
        let plainItems =
            unplaced.map { text.plain($0) }
            + [text.plain(folder: folder, passwordNotice: notice)].compactMap { $0 }
        guard !plainItems.isEmpty else {
            return
        }
        let html = textParts(in: part, subtype: "text/html")
        let plain = textParts(in: part, subtype: "text/plain")
        if let target = html.first(where: { quoted($0) }) ?? html.last, let content = target.text {
            let insertion = HTML.endOfOwnText(in: content)
            setText(target, content[..<insertion] + "<div><br></div>" + htmlItems.joined() + content[insertion...])
        } else if let target = plain.first(where: { quoted($0) }) ?? plain.last, let content = target.text {
            setText(target, insertingInPlain(plainItems.joined(separator: "\n\n"), into: content))
        } else if part.isMultipart {
            // No text to add to, in a structure the tests haven't shown. The links mustn't be lost.
            part.children.append(makeText("plain", plainItems.joined(separator: "\n\n") + "\n"))
        }
    }

    /// Inserts text before the first quoted line, or at the end, separated by blank lines.
    private func insertingInPlain(_ block: String, into content: String) -> String {
        let lines = content.components(separatedBy: "\n")
        if let quote = lines.firstIndex(where: { $0.hasPrefix(">") }) {
            let before = lines[..<quote].joined(separator: "\n").trimmingTrailingNewlines()
            let after = lines[quote...].joined(separator: "\n")
            return (before.isEmpty ? "" : before + "\n\n") + block + "\n\n" + after
        }
        let trimmed = content.trimmingTrailingNewlines()
        return (trimmed.isEmpty ? "" : trimmed + "\n\n") + block + "\n"
    }

    private func quoted(_ part: MimePart) -> Bool {
        guard let content = part.text else {
            return false
        }
        if part.contentType == "text/html" {
            let end = content.range(of: "</body>", options: [.caseInsensitive, .backwards])?.lowerBound
            return HTML.endOfOwnText(in: content) < (end ?? content.endIndex)
        }
        return content.components(separatedBy: "\n").contains { $0.hasPrefix(">") }
    }

    /// The text parts of a branch, without looking into nested alternatives, which are branches of their own.
    private func textParts(in part: MimePart, subtype: String) -> [MimePart] {
        if part.isMultipart {
            guard part.contentType != "multipart/alternative" else {
                return []
            }
            return part.children.flatMap { textParts(in: $0, subtype: subtype) }
        }
        return part.isText && part.contentType == subtype ? [part] : []
    }

    // MARK: - Building parts

    private func linkedIndexes(in part: MimePart) -> [Int] {
        if part.isMultipart {
            return part.children.flatMap { linkedIndexes(in: $0) }
        }
        guard let index = indexOfPart[ObjectIdentifier(part)], links[index] != nil else {
            return []
        }
        return [index]
    }

    private func makeText(_ subtype: String, _ content: String) -> MimePart {
        let part = MimePart(fields: [MimePart.Field(name: "Content-Type", raw: " text/\(subtype)")])
        setText(part, content)
        return part
    }

    /// Writes a text part as UTF-8, also in the HTML's own `<meta>` charset, so that file names keep their accents.
    private func setText(_ part: MimePart, _ content: String) {
        part.setText(part.contentType == "text/html" ? HTML.declaringUTF8(content) : content, eol: eol)
    }

    /// Joins neighbouring text parts of the same kind, so text, link and text become one part.
    private func merged(_ children: [MimePart]) -> [MimePart] {
        var result: [MimePart] = []
        for child in children {
            if let previous = result.last, previous.isText, child.isText, previous.contentType == child.contentType,
                let first = previous.text, let second = child.text
            {
                let separator = first.isEmpty || first.hasSuffix("\n") || second.hasPrefix("\n") ? "" : "\n"
                setText(
                    previous,
                    previous.contentType == "text/html" ? joinedHTML(first, second) : first + separator + second)
            } else {
                result.append(child)
            }
        }
        return result
    }

    /// Joins two HTML documents or fragments, keeping the first document's `<html>`, `<head>` and `<body>`.
    private func joinedHTML(_ first: String, _ second: String) -> String {
        let one = HTMLDocument(first)
        let two = HTMLDocument(second)
        let (prefix, suffix) = one.prefix.isEmpty ? (two.prefix, two.suffix) : (one.prefix, one.suffix)
        return prefix + one.body + two.body + suffix
    }

    /// Makes a message that is only a file into a text message with the file's links.
    private func replaceRootFile(_ root: MimePart, with link: LinkedFile) {
        let block = [text.plain(link), text.plain(folder: folder, passwordNotice: notice)].compactMap { $0 }
        for name in ["Content-Disposition", "Content-ID", "Content-Description", "Content-Type"] {
            root.removeField(name)
        }
        setText(root, block.joined(separator: "\n\n") + "\n")
    }

    /// Gives the root the content of the part that replaced it, keeping the root's own headers.
    private func adoptContent(of part: MimePart, into root: MimePart) {
        let content = Set(["content-type", "content-transfer-encoding", "content-disposition", "content-id"])
        root.fields =
            root.fields.filter { !content.contains($0.name.lowercased()) }
            + part.fields.filter { content.contains($0.name.lowercased()) }
        root.body = part.body
        root.children = part.children
        root.preamble = part.preamble
        root.epilogue = part.epilogue
    }
}

/// An HTML document split around the inside of its `<body>`. A fragment is all body.
private struct HTMLDocument {
    var prefix = ""
    var body: String
    var suffix = ""

    init(_ html: String) {
        body = html
        guard let open = html.range(of: #"<body\b[^>]*>"#, options: [.regularExpression, .caseInsensitive]) else {
            return
        }
        let close = html.range(of: "</body>", options: [.caseInsensitive, .backwards])?.lowerBound ?? html.endIndex
        guard open.upperBound <= close else {
            return
        }
        (prefix, body, suffix) = (
            String(html[..<open.upperBound]), String(html[open.upperBound..<close]), String(html[close...])
        )
    }
}

extension String {
    fileprivate func trimmingTrailingNewlines() -> String {
        var result = self
        while result.hasSuffix("\n") || result.hasSuffix("\r") {
            result.removeLast()
        }
        return result
    }
}
