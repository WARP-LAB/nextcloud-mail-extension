import Foundation

/// Decides which files in a message become links (FR3).
struct LinkPolicy {
    enum Rule: Equatable {
        case allAttachments
        /// Only files whose decoded size is larger than this many bytes.
        case largerThan(bytes: Int)
        /// All the files when their decoded sizes together are larger than this many bytes, else none.
        case togetherLargerThan(bytes: Int)
    }

    var rule: Rule
    /// Whether images pasted into the body follow the rule. When false, they stay in the email.
    var pastedImagesBecomeLinks = true

    /// The files that become links, in document order. Images in the signature never do.
    ///
    /// `signatureContentIDs` come from the first send call, because only its HTML marks the signature
    /// (docs/MAIL.md). See `signatureContentIDs(in:)`. `isSignatureFile` names the signature's images that an
    /// earlier call found, which a later call can't tell by their Content-IDs. Files that stay in the email don't
    /// count towards `togetherLargerThan`.
    func linkedFiles(
        in message: MimeMessage, signatureContentIDs: Set<String>,
        isSignatureFile: (MessageFile) -> Bool = { _ in false }
    ) -> [MessageFile] {
        let files = message.files.filter { file in
            if let contentID = file.contentID?.lowercased(), signatureContentIDs.contains(contentID) {
                return false
            }
            return !isSignatureFile(file) && (pastedImagesBecomeLinks || !Self.isPastedImage(file))
        }
        switch rule {
        case .allAttachments:
            return files
        case .largerThan(let bytes):
            return files.filter { $0.decodedSize > bytes }
        case .togetherLargerThan(let bytes):
            return files.reduce(0) { $0 + $1.decodedSize } > bytes ? files : []
        }
    }

    /// Mail names pasted images `PastedGraphic-1.png` and so on, which is the only way to tell them from image
    /// files that were dropped in (docs/MAIL.md, docs/RISKS.md R7).
    static func isPastedImage(_ file: MessageFile) -> Bool {
        file.contentType.hasPrefix("image/")
            && file.filename.range(of: #"^PastedGraphic-\d+\.[A-Za-z0-9]+$"#, options: .regularExpression) != nil
    }

    /// The Content-IDs of the images inside `<div id="AppleMailSignature">`, lowercased.
    static func signatureContentIDs(in message: MimeMessage) -> Set<String> {
        var found = Set<String>()
        for part in message.textParts("html") {
            guard let html = part.text, let signature = HTML.signatureRange(in: html) else {
                continue
            }
            for match in html[signature].matches(of: #/cid:([^"'\s>]+)/#) {
                found.insert(String(match.1).lowercased())
            }
        }
        return found
    }
}

/// Small helpers for the HTML that Mail writes.
enum HTML {
    static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    /// The range of `<div id="AppleMailSignature">` and its contents, up to its matching `</div>`.
    static func signatureRange(in html: String) -> Range<String.Index>? {
        guard let start = html.range(of: #"<div[^>]*id=["']AppleMailSignature["'][^>]*>"#, options: .regularExpression)
        else {
            return nil
        }
        var depth = 1
        var cursor = start.upperBound
        while depth > 0,
            let tag = html.range(of: #"</?div\b[^>]*>"#, options: .regularExpression, range: cursor..<html.endIndex)
        {
            depth += html[tag].hasPrefix("</") ? -1 : 1
            cursor = tag.upperBound
        }
        return start.lowerBound..<cursor
    }

    /// Changes the charset in the HTML's `<meta>` tags to UTF-8, for HTML that is about to be written as UTF-8.
    static func declaringUTF8(_ html: String) -> String {
        html.replacing(#/(<meta\b[^>]*?charset=["']?)[A-Za-z0-9_.:-]+/#.ignoresCase()) { match in
            match.1 + "utf-8"
        }
    }

    /// Where the user's own text ends: before quoted messages, or else before `</body>`, or else at the end.
    ///
    /// A `blockquote type="cite"` straight inside `<div class="Apple-Mail-URLShareWrapperClass">` isn't a quote:
    /// Mail puts what's shared from another app, or set by AppleScript, there (docs/MAIL.md).
    static func endOfOwnText(in html: String) -> String.Index {
        let quote = #/<div[^>]*class=["']AppleOriginalContents["']|<blockquote[^>]*type=["']cite["']/#.ignoresCase()
        let shared = #/<div[^>]*class=["']Apple-Mail-URLShareWrapperClass["'][^>]*>\s*$/#.ignoresCase()
        for match in html.matches(of: quote) where html[..<match.range.lowerBound].firstMatch(of: shared) == nil {
            return match.range.lowerBound
        }
        if let range = html.range(of: "</body>", options: [.caseInsensitive, .backwards]) {
            return range.lowerBound
        }
        return html.endIndex
    }
}
