import AppKit
import MailKit
import SwiftUI

/// Answers the host app's Test from Mail when a message window opens. Until the password popover arrives in task T6,
/// the toolbar popover shows the account the extension reads, with its own Test connection button.
final class ComposeHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        Task {
            await Self.answerMailCheck()
        }
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {}

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        StatusPopover()
    }

    /// Runs the connection check if the host app asked for one in the last two minutes (R17, R18).
    static func answerMailCheck() async {
        guard let group = SharedStorage.appGroupIdentifier, let mailCheck = MailCheck(groupIdentifier: group),
            let request = mailCheck.pendingRequest()
        else {
            return
        }
        let report = await ConnectionCheck.runWithSharedStorage()
        try? mailCheck.answer(request, with: report)
    }
}

private final class StatusPopover: MEExtensionViewController {
    override func loadView() {
        let hosting = NSHostingView(rootView: StatusView())
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 220)
        view = hosting
        preferredContentSize = hosting.frame.size
    }
}

private struct StatusView: View {
    @State private var report: ConnectionCheck.Report?
    @State private var checking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NextcloudAppleMail").font(.headline)
            Text(Self.account)
            Button(checking ? "Checking…" : "Test connection") {
                checking = true
                Task {
                    report = await ConnectionCheck.runWithSharedStorage()
                    checking = false
                }
            }
            .disabled(checking)
            if let report {
                Text(report.text)
                    .foregroundStyle(report.passed ? Color.primary : Color.red)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 380, height: 220, alignment: .topLeading)
    }

    private static var account: String {
        guard let group = SharedStorage.appGroupIdentifier else {
            return "No App Group identifier in Info.plist."
        }
        do {
            guard let account = try Credentials(group: group).load() else {
                return "Not logged in. Log in in the NextcloudAppleMail app."
            }
            return "Logged in to \(account.server.host ?? account.server.absoluteString) as \(account.loginName)."
        } catch {
            return "The app password couldn't be read. \(error.localizedDescription)"
        }
    }
}
