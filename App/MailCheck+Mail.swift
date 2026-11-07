import AppKit

extension MailCheck {
    /// Asks the extension to run the connection check, opens a new message window in Mail so that it runs, and
    /// waits for its answer. Nil if none came in time.
    func askInMail(wait: TimeInterval = 60) async throws -> Answer? {
        let request = try request()
        Self.openNewMessageInMail()
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline {
            try await Task.sleep(nanoseconds: 500_000_000)
            if let answer = answer(to: request) {
                return answer
            }
        }
        return nil
    }

    static func openNewMessageInMail() {
        guard let url = URL(string: "mailto:") else {
            return
        }
        let mail = URL(fileURLWithPath: "/System/Applications/Mail.app")
        NSWorkspace.shared.open([url], withApplicationAt: mail, configuration: NSWorkspace.OpenConfiguration())
    }

    static let noAnswer =
        "The extension didn't answer within a minute. Check that a new message window opened in Mail, and that "
        + "NextcloudMailExtension is turned on in Mail's Settings > Extensions."
}
