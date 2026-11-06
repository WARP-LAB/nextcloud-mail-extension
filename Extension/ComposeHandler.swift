import AppKit
import MailKit
import SwiftUI

/// The toolbar popover, where the user sets the email's password (FR7), and the host app's Test from Mail, which
/// runs when a message window opens.
final class ComposeHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        // A reopened draft may already have its message ID, which finds a password kept for it.
        let headers = session.mailMessage.headers ?? [:]
        let messageID = headers.first { $0.key.lowercased() == "x-universally-unique-identifier" }?.value.first
        if let messageID {
            MessagePasswords.shared.link(context: session.composeContext.contextID, message: messageID)
        }
        Task {
            await Self.answerMailCheck()
        }
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {}

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        PasswordPopover(context: session.composeContext.contextID)
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

private final class PasswordPopover: MEExtensionViewController {
    private let context: UUID

    init(context: UUID) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func loadView() {
        let hosting = NSHostingView(rootView: PasswordView(context: context))
        hosting.frame = NSRect(x: 0, y: 0, width: 380, height: 250)
        view = hosting
        preferredContentSize = hosting.frame.size
    }
}

private struct PasswordView: View {
    let context: UUID
    @State private var password: String
    @State private var report: ConnectionCheck.Report?
    @State private var checking = false

    init(context: UUID) {
        self.context = context
        _password = State(initialValue: MessagePasswords.shared.shown(context: context))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NextcloudAppleMail").font(.headline)
            SecureField("Password for this email's links", text: $password)
                .textFieldStyle(.roundedBorder)
                // Saved at every change, because the popover can close without the field ending its editing.
                .onChange(of: password) { _, value in
                    MessagePasswords.shared.set(value, context: context)
                }
            Text(
                "Empty means the links need no password. The email says that they need one, but not which: give it "
                    + "to the recipients some other way."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                Text(Self.account).font(.footnote)
                Spacer()
                Button(checking ? "Checking…" : "Test connection") {
                    checking = true
                    Task {
                        report = await ConnectionCheck.runWithSharedStorage()
                        checking = false
                    }
                }
                .disabled(checking)
            }
            if let report {
                Text(report.text)
                    .font(.footnote)
                    .foregroundStyle(report.passed ? Color.primary : Color.red)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(width: 380, height: 250, alignment: .topLeading)
    }

    private static var account: String {
        guard let group = SharedStorage.appGroupIdentifier else {
            return "No App Group identifier in Info.plist."
        }
        do {
            guard let account = try Credentials(group: group).load() else {
                return "Not logged in. Log in in the NextcloudAppleMail app."
            }
            return "\(account.loginName) on \(account.server.host ?? account.server.absoluteString)"
        } catch {
            return "The app password couldn't be read."
        }
    }
}
