import Foundation

/// The send check's warnings (FR5, FR6, docs/ARCHITECTURE.md, "Send warnings"). Mail shows at most one, with Cancel
/// and Send Anyway, and FR5 needs a file while FR6 needs none, so at most one applies.
enum SendWarnings {
    /// The warning for this message, or nil to send it without one.
    ///
    /// - Parameters:
    ///   - message: what the send check got: with Sign off the whole message, and with Sign on the first send call's
    ///     output, whose files may already be links (docs/MAIL.md).
    ///   - signOn: Mail's Sign toggle, read at send.
    ///   - linkedEarlier: how many files the first send call turned into links for this message.
    ///   - choice: the email's choice in the toolbar popover of which files become links.
    static func warning(
        for message: MimeMessage, signOn: Bool, settings: Settings, linkedEarlier: Int,
        choice: LinkChoice = .useSettings
    ) -> String? {
        let signature = LinkPolicy.signatureContentIDs(in: message)
        if settings.warnIfSignOff && !signOn {
            let files = settings.linkPolicy(for: choice).linkedFiles(in: message, signatureContentIDs: signature)
            if !files.isEmpty {
                return signOffWarning(files.map(\.filename))
            }
        }
        if !settings.warningPhrases.isEmpty {
            // Any file counts, a pasted image or one that became a link too, but not an image in the signature.
            let attachments = message.files.filter { file in
                !(file.contentID.map { signature.contains($0.lowercased()) } ?? false)
            }
            if attachments.isEmpty && linkedEarlier == 0,
                let phrase = TextCheck.firstPhrase(settings.warningPhrases, in: ownText(of: message))
            {
                return "Your message mentions “\(phrase)” but has no attachment."
            }
        }
        return nil
    }

    /// FR5's text: the files, and how to turn on Sign.
    static func signOffWarning(_ names: [String]) -> String {
        let list = names.map { "“\($0)”" }.joined(separator: ", ")
        let these = names.count == 1 ? "This file isn't" : "These files aren't"
        return "\(these) uploaded to Nextcloud, because Sign is off: \(list). To send links instead, click Cancel, "
            + "turn on Sign with the badge button at the right of the subject line, and send again. Send Anyway "
            + "sends the files attached."
    }

    /// The user's own text: from the HTML, which the send check gets, else from the plain text (docs/MAIL.md).
    static func ownText(of message: MimeMessage) -> String {
        let html = message.textParts("html").compactMap(\.text)
        if !html.isEmpty {
            return html.map { TextCheck.ownText(html: $0) }.joined(separator: " ")
        }
        return message.textParts("plain").compactMap(\.text).map { TextCheck.ownText(plain: $0) }.joined(separator: " ")
    }
}
