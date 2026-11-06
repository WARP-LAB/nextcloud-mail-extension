import Foundation

/// RFC 2047 encoded words in header fields, such as `=?utf-8?Q?P=C4=81rskats?=` in a subject.
enum EncodedWords {
    /// The header's text with its encoded words decoded. Space between two encoded words is dropped, as the RFC
    /// says, and a word that can't be decoded stays as it was.
    static func decode(_ header: String) -> String {
        let word = #/=\?([^?\s]+)\?([QqBb])\?([^?\s]*)\?=/#
        var output = ""
        var rest = header[...]
        var afterWord = false
        while let match = rest.firstMatch(of: word) {
            let between = rest[..<match.range.lowerBound]
            if !(afterWord && between.allSatisfy(\.isWhitespace)) {
                output += between
            }
            if let decoded = decode(String(match.3), encoding: String(match.2), charset: String(match.1)) {
                output += decoded
                afterWord = true
            } else {
                output += match.0
                afterWord = false
            }
            rest = rest[match.range.upperBound...]
        }
        return output + rest
    }

    private static func decode(_ text: String, encoding: String, charset: String) -> String? {
        // A charset may carry a language, as in `utf-8*lv` (RFC 2231).
        let charset = String(charset.prefix { $0 != "*" })
        let bytes: Data?
        if encoding.uppercased() == "B" {
            bytes = Data(base64Encoded: text, options: .ignoreUnknownCharacters)
        } else {
            bytes = TransferEncoding.decodeQuotedPrintable(Data(text.replacingOccurrences(of: "_", with: "=20").utf8))
        }
        return bytes.flatMap { TransferEncoding.text($0, charset: charset) }
    }
}
