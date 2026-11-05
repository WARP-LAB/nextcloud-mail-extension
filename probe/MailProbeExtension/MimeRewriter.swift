import Foundation

struct StrippedPart {
    let filename: String
    let contentType: String
    let encodedBytes: Int
}

struct RewriteOutcome {
    let data: Data
    let stripped: [StrippedPart]
    let notedPlain: Bool
    let notedHTML: Bool
}

final class MimePart {
    let headers: [String: String]
    let headerNames: [String]
    let headerRange: Range<Data.Index>
    let bodyRange: Range<Data.Index>
    fileprivate(set) var children: [MimePart] = []

    fileprivate init(headers: [String: String], headerNames: [String], headerRange: Range<Data.Index>, bodyRange: Range<Data.Index>) {
        self.headers = headers
        self.headerNames = headerNames
        self.headerRange = headerRange
        self.bodyRange = bodyRange
    }

    var contentType: String {
        let value = headers["content-type"] ?? "text/plain"
        return value.split(separator: ";", maxSplits: 1).first.map { $0.trimmingCharacters(in: .whitespaces).lowercased() } ?? "text/plain"
    }

    var boundary: String? {
        guard contentType.hasPrefix("multipart/") else { return nil }
        return headers["content-type"].flatMap { Self.parameter("boundary", in: $0) }
    }

    var transferEncoding: String {
        (headers["content-transfer-encoding"] ?? "7bit").trimmingCharacters(in: .whitespaces).lowercased()
    }

    var filename: String? {
        headers["content-disposition"].flatMap { Self.parameter("filename", in: $0) }
            ?? headers["content-type"].flatMap { Self.parameter("name", in: $0) }
    }

    var isAttachment: Bool {
        guard !contentType.hasPrefix("multipart/") else { return false }
        let disposition = (headers["content-disposition"] ?? "").lowercased()
        let type = (headers["content-type"] ?? "").lowercased()
        return disposition.hasPrefix("attachment") || disposition.contains("filename") || type.contains("name=") || type.contains("name*")
    }

    /// Reads a parameter from a structured header, including the `name*=utf-8''...` form.
    static func parameter(_ name: String, in header: String) -> String? {
        var segments: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false
        for character in header {
            if escaped {
                current.append(character)
                escaped = false
            } else if inQuotes && character == "\\" {
                escaped = true
            } else if character == "\"" {
                inQuotes.toggle()
            } else if character == ";" && !inQuotes {
                segments.append(current)
                current = ""
            } else {
                current.append(character)
            }
        }
        segments.append(current)

        for segment in segments.dropFirst() {
            guard let equals = segment.firstIndex(of: "=") else { continue }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == name { return value }
            if key == name + "*" {
                let encoded = value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false).last.map(String.init) ?? value
                return encoded.removingPercentEncoding ?? encoded
            }
        }
        return nil
    }
}

/// A small MIME walker: enough to drop attachment parts and add a note to the text parts.
final class MimeMessage {
    let data: Data
    let usesCRLF: Bool
    private(set) var root: MimePart!

    private var eol: Data { Data((usesCRLF ? "\r\n" : "\n").utf8) }

    init(_ data: Data) {
        self.data = data
        if let firstNewline = data.firstIndex(of: 0x0A), firstNewline > data.startIndex {
            usesCRLF = data[firstNewline - 1] == 0x0D
        } else {
            usesCRLF = false
        }
        root = parsePart(data.startIndex..<data.endIndex)
    }

    var structure: String {
        var lines: [String] = []
        describe(root, depth: 0, into: &lines)
        return lines.joined(separator: "\n")
    }

    /// Returns the message without its attachments, or only without those over `limit` decoded bytes
    /// if a limit is set. A message that would be left with no parts at all, such as one that is only
    /// an attachment, is returned unchanged apart from the header.
    func rewritten(note: String, removingOver limit: Int? = nil) -> RewriteOutcome {
        var stripped: [StrippedPart] = []
        collectAttachments(root, over: limit, into: &stripped)
        var context = NoteContext(summary: note, stripped: stripped, limit: limit)

        var output = Data()
        if let body = serialize(root, &context) {
            output.append(Data("X-MailProbe: \(note); stripped=\(stripped.count)".utf8))
            output.append(eol)
            output.append(body)
            return RewriteOutcome(data: output, stripped: stripped, notedPlain: context.notedPlain, notedHTML: context.notedHTML)
        }

        output.append(Data("X-MailProbe: \(note); stripped=0; only-attachment".utf8))
        output.append(eol)
        output.append(data)
        return RewriteOutcome(data: output, stripped: [], notedPlain: false, notedHTML: false)
    }

    // MARK: - Parsing

    private func parsePart(_ range: Range<Data.Index>) -> MimePart {
        var headers: [String: String] = [:]
        var headerNames: [String] = []
        var lastName: String?
        var cursor = range.lowerBound
        var headerEnd = range.upperBound
        var bodyStart = range.upperBound

        while cursor < range.upperBound {
            let newline = data[cursor..<range.upperBound].firstIndex(of: 0x0A) ?? range.upperBound
            let next = min(newline + 1, range.upperBound)
            var lineEnd = newline
            if lineEnd > cursor, data[lineEnd - 1] == 0x0D { lineEnd -= 1 }

            if lineEnd == cursor {
                headerEnd = cursor
                bodyStart = next
                break
            }

            let line = String(data: data[cursor..<lineEnd], encoding: .isoLatin1) ?? ""
            if line.first == " " || line.first == "\t" {
                if let lastName {
                    headers[lastName, default: ""] += " " + line.trimmingCharacters(in: .whitespaces)
                }
            } else if let colon = line.firstIndex(of: ":") {
                let name = line[..<colon].lowercased()
                headerNames.append(name)
                if headers[name] == nil {
                    headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
                    lastName = name
                } else {
                    lastName = nil
                }
            }
            cursor = next
        }

        let part = MimePart(headers: headers, headerNames: headerNames, headerRange: range.lowerBound..<headerEnd, bodyRange: bodyStart..<range.upperBound)
        if let boundary = part.boundary {
            part.children = parseChildren(of: part.bodyRange, boundary: boundary)
        }
        return part
    }

    private func parseChildren(of body: Range<Data.Index>, boundary: String) -> [MimePart] {
        let delimiter = Data("--\(boundary)".utf8)
        var children: [MimePart] = []
        var partStart: Data.Index?
        var searchStart = body.lowerBound
        var closed = false

        while let hit = data.range(of: delimiter, options: [], in: searchStart..<body.upperBound) {
            searchStart = hit.upperBound
            guard hit.lowerBound == body.lowerBound || data[hit.lowerBound - 1] == 0x0A else { continue }

            let isClosing = hit.upperBound + 2 <= body.upperBound && data[hit.upperBound] == 0x2D && data[hit.upperBound + 1] == 0x2D
            let lineEnd = data[hit.upperBound..<body.upperBound].firstIndex(of: 0x0A) ?? body.upperBound
            if !isClosing {
                let padding = data[hit.upperBound..<lineEnd]
                guard padding.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) else { continue }
            }

            if let start = partStart {
                var end = hit.lowerBound
                if end > start, data[end - 1] == 0x0A { end -= 1 }
                if end > start, data[end - 1] == 0x0D { end -= 1 }
                children.append(parsePart(start..<end))
            }
            if isClosing {
                closed = true
                break
            }
            partStart = min(lineEnd + 1, body.upperBound)
            searchStart = partStart!
        }

        if !closed, let start = partStart {
            children.append(parsePart(start..<body.upperBound))
        }
        return children
    }

    private func describe(_ part: MimePart, depth: Int, into lines: inout [String]) {
        var line = String(repeating: "  ", count: depth) + part.contentType
        if part.children.isEmpty {
            line += " \(part.transferEncoding) \(part.bodyRange.count)B"
        }
        if part.isAttachment {
            let disposition = part.headers["content-disposition"]?.split(separator: ";").first.map(String.init) ?? "none"
            line += " disposition=\(disposition) file=\"\(part.filename ?? "unnamed")\""
        }
        lines.append(line)
        part.children.forEach { describe($0, depth: depth + 1, into: &lines) }
    }

    // MARK: - Rewriting

    private struct NoteContext {
        let summary: String
        let stripped: [StrippedPart]
        let limit: Int?
        var notedPlain = false
        var notedHTML = false
    }

    private func removes(_ part: MimePart, over limit: Int?) -> Bool {
        guard part.isAttachment else { return false }
        guard let limit else { return true }
        return decodedSize(part) > limit
    }

    private func decodedSize(_ part: MimePart) -> Int {
        let body = Data(data[part.bodyRange])
        guard part.transferEncoding == "base64" else { return body.count }
        return Data(base64Encoded: body, options: .ignoreUnknownCharacters)?.count ?? body.count
    }

    private func collectAttachments(_ part: MimePart, over limit: Int?, into stripped: inout [StrippedPart]) {
        if removes(part, over: limit) {
            stripped.append(StrippedPart(filename: part.filename ?? "unnamed", contentType: part.contentType, encodedBytes: part.bodyRange.count))
        }
        part.children.forEach { collectAttachments($0, over: limit, into: &stripped) }
    }

    private func serialize(_ part: MimePart, _ context: inout NoteContext) -> Data? {
        if removes(part, over: context.limit) { return nil }

        var output = Data(data[part.headerRange])
        if output.last != 0x0A && !output.isEmpty { output.append(eol) }
        output.append(eol)

        guard let boundary = part.boundary, !part.children.isEmpty else {
            output.append(bodyWithNote(part, &context))
            return output
        }

        let kept = part.children.compactMap { serialize($0, &context) }
        guard !kept.isEmpty else { return nil }
        for child in kept {
            output.append(Data("--\(boundary)".utf8))
            output.append(eol)
            output.append(child)
            output.append(eol)
        }
        output.append(Data("--\(boundary)--".utf8))
        output.append(eol)
        return output
    }

    private func bodyWithNote(_ part: MimePart, _ context: inout NoteContext) -> Data {
        let isPlain = !part.isAttachment && part.contentType == "text/plain" && !context.notedPlain
        let isHTML = !part.isAttachment && part.contentType == "text/html" && !context.notedHTML
        let body = Data(data[part.bodyRange])
        guard isPlain || isHTML else { return body }

        if isPlain { context.notedPlain = true } else { context.notedHTML = true }
        let note = isPlain ? plainNote(context) : htmlNote(context)

        switch part.transferEncoding {
        case "base64":
            guard let decoded = Data(base64Encoded: body, options: .ignoreUnknownCharacters) else { return body }
            let options: Data.Base64EncodingOptions = usesCRLF
                ? [.lineLength76Characters, .endLineWithCarriageReturn, .endLineWithLineFeed]
                : [.lineLength76Characters, .endLineWithLineFeed]
            return inserting(Data(note.utf8), into: decoded, isHTML: isHTML).base64EncodedData(options: options)
        case "quoted-printable":
            return inserting(Data(note.replacingOccurrences(of: "=", with: "=3D").utf8), into: body, isHTML: isHTML)
        default:
            return inserting(Data(note.utf8), into: body, isHTML: isHTML)
        }
    }

    private func inserting(_ note: Data, into body: Data, isHTML: Bool) -> Data {
        var position = body.startIndex
        if isHTML {
            let tag = body.range(of: Data("<body".utf8)) ?? body.range(of: Data("<BODY".utf8))
            if let tag, let close = body[tag.upperBound...].firstIndex(of: 0x3E) {
                position = close + 1
            }
        }
        var output = Data(body[body.startIndex..<position])
        output.append(note)
        output.append(body[position...])
        return output
    }

    private func plainNote(_ context: NoteContext) -> String {
        let newline = usesCRLF ? "\r\n" : "\n"
        var lines = ["[MAILPROBE] \(context.summary) stripped=\(context.stripped.count)"]
        lines += context.stripped.map { " - \(asciiName($0.filename)) (\($0.encodedBytes) encoded bytes)" }
        return lines.joined(separator: newline) + newline + newline
    }

    private func htmlNote(_ context: NoteContext) -> String {
        let newline = usesCRLF ? "\r\n" : "\n"
        var lines = ["<div><b>[MAILPROBE]</b> \(context.summary) stripped=\(context.stripped.count)<br>"]
        lines += context.stripped.map { "\(escapedHTML(asciiName($0.filename))) (\($0.encodedBytes) encoded bytes)<br>" }
        lines.append("</div><br>")
        return lines.joined(separator: newline) + newline
    }

    private func asciiName(_ name: String) -> String {
        String(name.prefix(60).map { $0.isASCII && !$0.isNewline ? $0 : "?" })
    }

    private func escapedHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
