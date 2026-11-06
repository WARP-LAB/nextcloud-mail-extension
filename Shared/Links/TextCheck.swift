import Foundation

/// The text the user wrote, and FR6's phrases in it (docs/ARCHITECTURE.md, "FR6").
enum TextCheck {
    /// The user's own text in Mail's HTML: without quoted messages, the signature and tags, with entities decoded and
    /// spaces collapsed. Mail's wrapper for shared content isn't a quote, so its text stays (docs/MAIL.md).
    static func ownText(html: String) -> String {
        var html = html
        html = removing(#"<div[^>]*class=["']AppleOriginalContents["'][^>]*>"#, tag: "div", from: html)
        html = removing(#"<div[^>]*id=["']AppleMailSignature["'][^>]*>"#, tag: "div", from: html)
        html = removingQuotes(from: html)
        html = html.replacingOccurrences(
            of: #"<(style|script|head)\b[^>]*>.*?</\1>"#, with: " ",
            options: [.regularExpression, .caseInsensitive])
        html = html.replacingOccurrences(of: #"<[^>]*>"#, with: " ", options: .regularExpression)
        return collapsed(decodingEntities(html))
    }

    /// The user's own text in plain text: without lines quoted with `>`, and without a signature after `-- `.
    static func ownText(plain: String) -> String {
        var lines: [String] = []
        for line in plain.components(separatedBy: "\n") {
            if line == "-- " {
                break
            }
            if !line.hasPrefix(">") {
                lines.append(line)
            }
        }
        return collapsed(lines.joined(separator: " "))
    }

    /// The first phrase found in the text, ignoring case, also inside longer words, so "attach" finds "attached".
    static func firstPhrase(_ phrases: [String], in text: String) -> String? {
        phrases.first { phrase in
            let phrase = collapsed(phrase)
            return !phrase.isEmpty && text.range(of: phrase, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }

    // MARK: - Helpers

    /// Removes each element whose opening tag matches, up to its matching closing tag.
    private static func removing(_ opening: String, tag: String, from html: String) -> String {
        var html = html
        while let start = html.range(of: opening, options: [.regularExpression, .caseInsensitive]) {
            html.removeSubrange(start.lowerBound..<end(of: tag, after: start.upperBound, in: html))
        }
        return html
    }

    /// Removes `<blockquote type="cite">` quotes, but not the one inside Mail's wrapper for shared content.
    private static func removingQuotes(from html: String) -> String {
        var html = html
        var searchFrom = html.startIndex
        let quote = #"<blockquote[^>]*type=["']cite["'][^>]*>"#
        let shared = #/<div[^>]*class=["']Apple-Mail-URLShareWrapperClass["'][^>]*>\s*$/#.ignoresCase()
        while let start = html.range(
            of: quote, options: [.regularExpression, .caseInsensitive], range: searchFrom..<html.endIndex)
        {
            if html[..<start.lowerBound].firstMatch(of: shared) != nil {
                searchFrom = start.upperBound
                continue
            }
            html.removeSubrange(start.lowerBound..<end(of: "blockquote", after: start.upperBound, in: html))
            searchFrom = start.lowerBound
        }
        return html
    }

    /// Where the element opened just before `position` ends, counting nested elements of the same tag.
    private static func end(of tag: String, after position: String.Index, in html: String) -> String.Index {
        var depth = 1
        var cursor = position
        while depth > 0,
            let next = html.range(
                of: "</?\(tag)\\b[^>]*>", options: [.regularExpression, .caseInsensitive],
                range: cursor..<html.endIndex)
        {
            depth += html[next].hasPrefix("</") ? -1 : 1
            cursor = next.upperBound
        }
        return depth == 0 ? cursor : html.endIndex
    }

    private static func decodingEntities(_ text: String) -> String {
        let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'"]
        var text = text
        for (entity, character) in named {
            text = text.replacingOccurrences(of: entity, with: character, options: .caseInsensitive)
        }
        text = text.replacing(#/&#(x?)([0-9A-Fa-f]+);/#) { match in
            let value = UInt32(String(match.2), radix: match.1.isEmpty ? 10 : 16)
            return value.flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? String(match.0)
        }
        return text.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    }

    private static func collapsed(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
    }
}
