import Foundation

/// One MIME entity: its header fields, and either a body or child entities.
///
/// A part keeps its header fields and body exactly as written, so parts the rewriter doesn't change come out
/// byte for byte the same.
final class MimePart {
    struct Field {
        /// The name as written, such as `Content-Type`.
        var name: String
        /// Everything after the colon, including folded continuation lines, as written.
        var raw: String

        /// The value without folding and surrounding spaces.
        var value: String {
            raw.components(separatedBy: .newlines)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        }
    }

    var fields: [Field]
    /// The encoded body of a part without children.
    var body: Data
    var children: [MimePart]
    /// What a multipart has before its first boundary, including the line break before it.
    var preamble = Data()
    /// What a multipart has after its closing boundary, or nil for a line break.
    var epilogue: Data?

    init(fields: [Field], body: Data = Data(), children: [MimePart] = []) {
        self.fields = fields
        self.body = body
        self.children = children
    }

    func field(_ name: String) -> String? {
        fields.first { $0.name.lowercased() == name }?.value
    }

    /// A top-level header field of a message, read without parsing the rest, as for a large draft. `name` is
    /// lowercase.
    static func headerField(_ name: String, in message: Data) -> String? {
        let end =
            message.range(of: Data("\n\n".utf8))?.lowerBound ?? message.range(of: Data("\r\n\r\n".utf8))?.lowerBound
        let header = message[..<(end ?? message.endIndex)].prefix(256 * 1024)
        let text = (String(bytes: header, encoding: .utf8) ?? String(bytes: header, encoding: .isoLatin1) ?? "")
            .replacingOccurrences(of: "\r\n", with: "\n")
        var found: String?
        for line in text.components(separatedBy: "\n") {
            if line.isEmpty {
                break  // the end of the header
            }
            if let value = found, let first = line.first, first == " " || first == "\t" {
                found = value + " " + line.trimmingCharacters(in: .whitespaces)
                continue
            }
            if found != nil {
                break
            }
            if let colon = line.firstIndex(of: ":"), line[..<colon].lowercased() == name {
                found = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return found
    }

    /// Replaces the first field with this name, or adds one.
    func setField(_ name: String, _ value: String) {
        if let index = fields.firstIndex(where: { $0.name.lowercased() == name.lowercased() }) {
            fields[index].raw = " " + value
        } else {
            fields.append(Field(name: name, raw: " " + value))
        }
    }

    func removeField(_ name: String) {
        fields.removeAll { $0.name.lowercased() == name.lowercased() }
    }

    var contentType: String {
        let value = field("content-type") ?? "text/plain"
        let type = value.split(separator: ";", maxSplits: 1).first.map(String.init) ?? value
        return type.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var isMultipart: Bool {
        contentType.hasPrefix("multipart/") && boundary != nil
    }

    var boundary: String? {
        field("content-type").flatMap { Self.parameter("boundary", in: $0) }
    }

    var transferEncoding: String {
        (field("content-transfer-encoding") ?? "7bit").trimmingCharacters(in: .whitespaces).lowercased()
    }

    var charset: String? {
        field("content-type").flatMap { Self.parameter("charset", in: $0) }
    }

    var filename: String? {
        field("content-disposition").flatMap { Self.parameter("filename", in: $0) }
            ?? field("content-type").flatMap { Self.parameter("name", in: $0) }
    }

    /// The Content-ID without its angle brackets.
    var contentID: String? {
        field("content-id")?.trimmingCharacters(in: CharacterSet(charactersIn: "<> "))
    }

    /// A file rather than message text: a part with an attachment disposition or a file name.
    var isFile: Bool {
        guard !contentType.hasPrefix("multipart/") else {
            return false
        }
        let disposition = (field("content-disposition") ?? "").lowercased()
        return disposition.hasPrefix("attachment") || filename != nil
    }

    /// Message text: a `text/plain` or `text/html` part that isn't a file.
    var isText: Bool {
        (contentType == "text/plain" || contentType == "text/html") && !isFile
    }

    var decodedBody: Data {
        TransferEncoding.decode(body, encoding: transferEncoding)
    }

    /// The text of a text part, with lines ending in `\n`, or nil if its charset isn't one this code handles.
    var text: String? {
        TransferEncoding.text(decodedBody, charset: charset)?.replacingOccurrences(of: "\r\n", with: "\n")
    }

    /// Replaces the text, written as quoted-printable UTF-8.
    func setText(_ text: String, eol: String) {
        setField("Content-Type", "\(contentType); charset=utf-8")
        setField("Content-Transfer-Encoding", "quoted-printable")
        body = TransferEncoding.encodeQuotedPrintable(text, eol: eol)
    }

    /// Reads a parameter of a structured header, including the RFC 2231 `name*=utf-8''…` form.
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
            guard let equals = segment.firstIndex(of: "=") else {
                continue
            }
            let key = segment[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = segment[segment.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if key == name {
                return value
            }
            if key == name + "*" {
                let encoded =
                    value.split(separator: "'", maxSplits: 2, omittingEmptySubsequences: false)
                    .last.map(String.init) ?? value
                return encoded.removingPercentEncoding ?? encoded
            }
        }
        return nil
    }
}

/// A file in a message, as the link policy and the uploads see it.
struct MessageFile {
    /// The file's position among the message's files, in document order.
    let index: Int
    let filename: String
    let contentType: String
    let contentID: String?
    let decodedSize: Int
    let part: MimePart

    var data: Data {
        part.decodedBody
    }
}

/// A parsed message that can be changed and written out again.
final class MimeMessage {
    let original: Data
    /// The line ending the message uses, `\r\n` or `\n`.
    let eol: String
    var root: MimePart

    init(_ data: Data) {
        original = data
        if let newline = data.firstIndex(of: 0x0A), newline > data.startIndex, data[newline - 1] == 0x0D {
            eol = "\r\n"
        } else {
            eol = "\n"
        }
        root = MimeParser(data: data).part(in: data.startIndex..<data.endIndex)
    }

    /// The message's files in document order.
    var files: [MessageFile] {
        var found: [MimePart] = []
        collectFiles(root, into: &found)
        return found.enumerated().map { index, part in
            MessageFile(
                index: index,
                filename: part.filename ?? "attachment",
                contentType: part.contentType,
                contentID: part.contentID,
                decodedSize: TransferEncoding.decodedSize(part.body, encoding: part.transferEncoding),
                part: part
            )
        }
    }

    /// The message's text parts of one subtype, `plain` or `html`, in document order.
    func textParts(_ subtype: String) -> [MimePart] {
        var found: [MimePart] = []
        collectText(root, subtype: "text/\(subtype)", into: &found)
        return found
    }

    func data() -> Data {
        serialize(root)
    }

    private func collectFiles(_ part: MimePart, into found: inout [MimePart]) {
        if part.isMultipart {
            for child in part.children {
                collectFiles(child, into: &found)
            }
        } else if part.isFile {
            found.append(part)
        }
    }

    private func collectText(_ part: MimePart, subtype: String, into found: inout [MimePart]) {
        if part.isMultipart {
            for child in part.children {
                collectText(child, subtype: subtype, into: &found)
            }
        } else if part.isText && part.contentType == subtype {
            found.append(part)
        }
    }

    private func serialize(_ part: MimePart) -> Data {
        var output = Data()
        for field in part.fields {
            output.append(Data("\(field.name):\(field.raw)".utf8))
            output.append(Data(eol.utf8))
        }
        output.append(Data(eol.utf8))
        guard part.isMultipart, let boundary = part.boundary else {
            output.append(part.body)
            return output
        }
        output.append(part.preamble)
        for (number, child) in part.children.enumerated() {
            if number > 0 {
                output.append(Data(eol.utf8))
            }
            output.append(Data("--\(boundary)\(eol)".utf8))
            output.append(serialize(child))
        }
        output.append(Data("\(eol)--\(boundary)--".utf8))
        output.append(part.epilogue ?? Data(eol.utf8))
        return output
    }
}

/// Splits raw message bytes into parts.
private struct MimeParser {
    let data: Data

    func part(in range: Range<Data.Index>) -> MimePart {
        var fields: [MimePart.Field] = []
        var cursor = range.lowerBound
        var bodyStart = range.upperBound

        while cursor < range.upperBound {
            let newline = data[cursor..<range.upperBound].firstIndex(of: 0x0A) ?? range.upperBound
            let next = min(newline + 1, range.upperBound)
            var lineEnd = newline
            if lineEnd > cursor, data[lineEnd - 1] == 0x0D {
                lineEnd -= 1
            }
            if lineEnd == cursor {
                bodyStart = next
                break
            }
            let line = String(bytes: data[cursor..<lineEnd], encoding: .isoLatin1) ?? ""
            let ending = String(bytes: data[lineEnd..<newline], encoding: .isoLatin1) ?? ""
            if line.first == " " || line.first == "\t", !fields.isEmpty {
                fields[fields.count - 1].raw += ending + "\n" + line
            } else if let colon = line.firstIndex(of: ":") {
                fields.append(
                    MimePart.Field(name: String(line[..<colon]), raw: String(line[line.index(after: colon)...])))
            }
            cursor = next
        }

        let body = Data(data[bodyStart..<range.upperBound])
        let part = MimePart(fields: fields, body: body)
        if part.isMultipart, let boundary = part.boundary {
            fill(part, from: bodyStart..<range.upperBound, boundary: boundary)
            part.body = Data()
        }
        return part
    }

    /// Reads a multipart's children, and what comes before and after them.
    private func fill(_ multipart: MimePart, from body: Range<Data.Index>, boundary: String) {
        let delimiter = Data("--\(boundary)".utf8)
        var children: [MimePart] = []
        var partStart: Data.Index?
        var searchStart = body.lowerBound
        defer {
            multipart.children = children
        }

        while let hit = data.range(of: delimiter, options: [], in: searchStart..<body.upperBound) {
            searchStart = hit.upperBound
            guard hit.lowerBound == body.lowerBound || data[hit.lowerBound - 1] == 0x0A else {
                continue
            }
            let isClosing =
                hit.upperBound + 2 <= body.upperBound
                && data[hit.upperBound] == 0x2D && data[hit.upperBound + 1] == 0x2D
            let lineEnd = data[hit.upperBound..<body.upperBound].firstIndex(of: 0x0A) ?? body.upperBound
            if !isClosing {
                let padding = data[hit.upperBound..<lineEnd]
                guard padding.allSatisfy({ $0 == 0x20 || $0 == 0x09 || $0 == 0x0D }) else {
                    continue
                }
            }
            if let start = partStart {
                var end = hit.lowerBound
                if end > start, data[end - 1] == 0x0A {
                    end -= 1
                }
                if end > start, data[end - 1] == 0x0D {
                    end -= 1
                }
                children.append(part(in: start..<end))
            } else {
                multipart.preamble = Data(data[body.lowerBound..<hit.lowerBound])
            }
            if isClosing {
                multipart.epilogue = Data(data[hit.upperBound + 2..<body.upperBound])
                return
            }
            partStart = min(lineEnd + 1, body.upperBound)
            searchStart = partStart ?? body.upperBound
        }
        if let start = partStart {
            children.append(part(in: start..<body.upperBound))
        }
    }
}
