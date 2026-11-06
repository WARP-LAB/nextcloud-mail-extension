import AppKit
import MailKit
import SwiftUI

/// The send check's warnings (FR5, FR6), the toolbar popover, where the user sets which of the email's files become
/// links (FR3), its password (FR7) and its expiry (FR4), and the host app's Test from Mail, which runs when a message
/// window opens.
final class ComposeHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        // A reopened draft may already have its message ID, which finds a password kept for it.
        let headers = session.mailMessage.headers ?? [:]
        let messageID = headers.first { $0.key.lowercased() == "x-universally-unique-identifier" }?.value.first
        if let messageID {
            MessageValues.passwords.link(context: session.composeContext.contextID, message: messageID)
            MessageValues.expiries.link(context: session.composeContext.contextID, message: messageID)
            MessageValues.linkChoices.link(context: session.composeContext.contextID, message: messageID)
        }
        Task {
            await Self.answerMailCheck()
        }
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {}

    /// Warns before sending, with Mail's Cancel and Send Anyway. Sign is read here, at send, because at compose start
    /// it can be wrong (docs/MAIL.md).
    func allowMessageSendForSession(_ session: MEComposeSession, completion: @escaping (Error?) -> Void) {
        let raw = session.mailMessage.rawData
        let signOn = session.composeContext.shouldSign
        let contextID = session.composeContext.contextID
        Task {
            let warning = await SecurityHandler.shared.sendWarning(raw: raw, signOn: signOn, contextID: contextID)
            completion(
                warning.map { MEComposeSessionError(.invalidBody, userInfo: [NSLocalizedDescriptionKey: $0]) })
        }
    }

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
        let hosting = NSHostingView(rootView: PopoverView(context: context))
        hosting.frame = NSRect(x: 0, y: 0, width: 400, height: PopoverView.height)
        view = hosting
        preferredContentSize = hosting.frame.size
    }
}

/// Which of the email's files become links (FR3), its password (FR7), its own link expiry if it should differ from
/// the settings' (FR4), and a way to the app's settings.
private struct PopoverView: View {
    static let height: CGFloat = 500

    let context: UUID
    private let settings: Settings
    @State private var choice: LinkChoice
    @State private var password: String
    @State private var passwordShown = false
    @State private var ownExpiry: Bool
    @State private var expiry: LinkExpiry
    @State private var report: ConnectionCheck.Report?
    @State private var checking = false

    init(context: UUID) {
        self.context = context
        let settings =
            SharedStorage.appGroupIdentifier.flatMap(SettingsStore.init(groupIdentifier:))?.load() ?? Settings()
        self.settings = settings
        _choice = State(
            initialValue: LinkChoice(stored: MessageValues.linkChoices.value(context: context, message: nil)))
        _password = State(initialValue: MessageValues.passwords.shown(context: context))
        let own = MessageValues.expiries.value(context: context, message: nil).flatMap {
            try? JSONDecoder().decode(LinkExpiry.self, from: Data($0.utf8))
        }
        _ownExpiry = State(initialValue: own != nil)
        _expiry = State(initialValue: own ?? settings.expiry)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("NextcloudAppleMail").font(.headline)
            Divider()
            linksSection
            Divider()
            Group {
                passwordSection
                Divider()
                expirySection
            }
            .disabled(choice == .keepAttached)
            Divider()
            HStack {
                Text(Self.account).font(.footnote)
                Spacer()
                Button("Settings…", action: Self.openApp)
                    .help(Self.settingsHelp)
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
        .frame(width: 400, height: Self.height, alignment: .topLeading)
    }

    /// FR3, for this email.
    private var linksSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("For this email")
            Picker("For this email", selection: $choice) {
                Text("Use settings").tag(LinkChoice.useSettings)
                Text("All files via Nextcloud").tag(LinkChoice.allFiles)
                Text("All files kept as attachments").tag(LinkChoice.keepAttached)
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
            .onChange(of: choice) { _, value in
                MessageValues.linkChoices.set(value == .useSettings ? "" : value.rawValue, context: context)
            }
        }
    }

    private var passwordSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Group {
                    if passwordShown {
                        TextField("Password for this email's links", text: $password)
                    } else {
                        SecureField("Password for this email's links", text: $password)
                    }
                }
                .textFieldStyle(.roundedBorder)
                // Saved at every change, because the popover can close without the field ending its editing.
                .onChange(of: password) { _, value in
                    MessageValues.passwords.set(value, context: context)
                }
                Button {
                    passwordShown.toggle()
                } label: {
                    Image(systemName: passwordShown ? "eye.slash" : "eye")
                }
                .buttonStyle(.borderless)
                .help(passwordShown ? "Hide the password" : "Show the password")
                .accessibilityLabel(passwordShown ? "Hide the password" : "Show the password")
            }
            Text(
                "Empty means the links need no password. The email says that they need one, but not which: give it "
                    + "to the recipients some other way."
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var expirySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Own link expiry for this email", isOn: $ownExpiry)
                .onChange(of: ownExpiry) { _, _ in saveExpiry() }
            if ownExpiry {
                Form {
                    ExpiryPicker(expiry: $expiry)
                }
                .formStyle(.columns)
                .onChange(of: expiry) { _, _ in saveExpiry() }
            } else {
                Text("Links expire \(settings.expiry.description), as in the settings.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Keeps the email's own expiry, or clears it so that the settings' applies.
    private func saveExpiry() {
        let json = ownExpiry ? (try? JSONEncoder().encode(expiry)).flatMap { String(bytes: $0, encoding: .utf8) } : nil
        MessageValues.expiries.set(json ?? "", context: context)
    }

    /// The Settings… button's tooltip, which the Mail checks also find it by.
    static let settingsHelp = "Open NextcloudAppleMail's settings"

    /// Opens the app the extension is in, `NextcloudAppleMail.app`, three folders up from the extension.
    private static func openApp() {
        let app = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
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
