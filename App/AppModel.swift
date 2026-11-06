import AppKit
import Foundation
import UserNotifications

/// The host app's state: the settings, the account, and any login or check in progress.
@MainActor
final class AppModel: ObservableObject {
    enum Login: Equatable {
        case idle
        /// Waiting for the user to log in on this page in the browser.
        case waiting(URL)
    }

    struct CheckResult: Equatable {
        var title: String
        var report: ConnectionCheck.Report?
    }

    /// Saved to the App Group at every change, where the extension reads them.
    @Published var settings: Settings {
        didSet {
            if settings != oldValue {
                store?.save(settings)
            }
        }
    }
    @Published private(set) var account: NextcloudAccount?
    @Published private(set) var login = Login.idle
    @Published private(set) var accountProblem: String?
    @Published private(set) var checking = false
    @Published private(set) var check: CheckResult?

    private let group = SharedStorage.appGroupIdentifier
    private let store: SettingsStore?
    private var loginTask: Task<Void, Never>?

    /// How long Nextcloud keeps a browser login open.
    private static let loginLifetime: TimeInterval = 20 * 60
    /// How long Test from Mail waits for the extension's answer.
    private static let mailCheckWait: TimeInterval = 60

    init() {
        store = group.flatMap(SettingsStore.init(groupIdentifier:))
        settings = store?.load() ?? Settings()
        // The extension's upload notifications come under the app's permission (R3).
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
        guard let group else {
            accountProblem = "No App Group identifier in Info.plist, so the extension can't read the settings."
            return
        }
        do {
            account = try Credentials(group: group).load()
        } catch {
            accountProblem = "The app password couldn't be read. \(error.localizedDescription)"
        }
    }

    // MARK: - Logging in and out

    /// Opens Nextcloud's login page in the browser, and waits for the user to log in there (FR2).
    func logIn() {
        accountProblem = nil
        let server: URL
        do {
            server = try ServerAddress.url(from: settings.server)
        } catch {
            accountProblem = error.localizedDescription
            return
        }
        settings.server = server.absoluteString
        loginTask?.cancel()
        loginTask = Task { await runLogin(server) }
    }

    func cancelLogin() {
        loginTask?.cancel()
        loginTask = nil
        login = .idle
    }

    private func runLogin(_ server: URL) async {
        defer {
            login = .idle
        }
        do {
            let flow = try await NextcloudClient.startLogin(server: server)
            login = .waiting(flow.loginURL)
            NSWorkspace.shared.open(flow.loginURL)
            let deadline = Date().addingTimeInterval(Self.loginLifetime)
            while Date() < deadline {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                if let account = try await NextcloudClient.pollLogin(flow) {
                    try save(account)
                    return
                }
            }
            accountProblem = "The login wasn't finished within 20 minutes. Log in again."
        } catch is CancellationError {
            return
        } catch {
            accountProblem = error.localizedDescription
        }
    }

    private func save(_ account: NextcloudAccount) throws {
        guard let group else {
            throw KeychainError(status: errSecMissingEntitlement)
        }
        try Credentials(group: group).save(account)
        self.account = account
        settings.server = account.server.absoluteString
        accountProblem = nil
    }

    /// Revokes the app password on the server and deletes it from the Keychain. If the server can't be reached, the
    /// app password is still deleted here, and the message says how to revoke it.
    func logOut() async {
        guard let account, let group else {
            return
        }
        var problem: String?
        do {
            try await NextcloudClient(account: account, userID: account.loginName).revokeAppPassword()
        } catch NextcloudError.unauthorized {
            problem = nil
        } catch {
            problem =
                "The app password couldn't be revoked on the server: \(error.localizedDescription) "
                + "Revoke it in Nextcloud's Settings > Security."
        }
        do {
            try Credentials(group: group).delete()
            self.account = nil
        } catch {
            problem = "The app password couldn't be deleted. \(error.localizedDescription)"
        }
        accountProblem = problem
    }

    // MARK: - Checks

    /// Runs the connection check in the host app.
    func testConnection() async {
        checking = true
        check = CheckResult(title: "Checking…")
        let report = await ConnectionCheck.runWithSharedStorage()
        check = CheckResult(title: "Checked by NextcloudMailExtension", report: report)
        checking = false
    }

    /// Asks the extension to run the connection check inside Mail, opens a new message window there so that it
    /// runs, and waits for its answer (R17, R18).
    func testFromMail() async {
        guard let group, let mailCheck = MailCheck(groupIdentifier: group) else {
            check = CheckResult(title: "No App Group container, so the extension can't be asked.")
            return
        }
        checking = true
        defer {
            checking = false
        }
        do {
            check = CheckResult(title: "Waiting for the extension in Mail's new message window…")
            if let answer = try await mailCheck.askInMail(wait: Self.mailCheckWait) {
                check = CheckResult(
                    title: "Checked by the extension in Mail. You can close the new message window.",
                    report: answer.report)
            } else {
                check = CheckResult(title: MailCheck.noAnswer)
            }
        } catch {
            check = CheckResult(title: "The extension couldn't be asked. \(error.localizedDescription)")
        }
    }
}
