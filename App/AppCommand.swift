import Foundation

/// The host app's command-line options, for checks without the window:
///
/// - `--check-storage`: the App Group and Keychain check, printed as JSON.
/// - `--check-connection`: the connection check that Test connection runs.
/// - `--check-from-mail`: the same check run by the extension, as Test from Mail does. It opens a new message window.
/// - `--use-test-account`, debug builds only: logs in to the test server in the environment, as `scripts/
///   use-test-account.sh` loads it from `.env`, and sets the upload directory to `NCME_TEST_DIRECTORY` (D14).
/// - `--log-out`, debug builds only: revokes the stored app password and deletes it.
/// - `--settings [<json>]`, debug builds only: prints the settings as JSON, after changing those in `<json>`.
/// - `--notification-status`, debug builds only: whether macOS lets the app post notifications.
/// - `--render-window`, debug builds only: the settings window drawn off screen, as a PNG in base64.
/// - `--debug-dumps on|off|take`, debug builds only: the copies of test messages that Mail passes the extension
///   (`DebugDumps`). `take` prints each as its name, a tab and the message in base64, and deletes them.
///
/// Each exits with 0 if it worked.
enum AppCommand {
    case checkStorage
    case checkConnection
    case checkFromMail
    case useTestAccount
    case logOut
    case settings(String?)
    case debugDumps(String)
    case renderWindow
    case notificationStatus

    init?(arguments: [String]) {
        if arguments.contains("--check-storage") {
            self = .checkStorage
        } else if arguments.contains("--check-connection") {
            self = .checkConnection
        } else if arguments.contains("--check-from-mail") {
            self = .checkFromMail
        } else if Self.debug && arguments.contains("--use-test-account") {
            self = .useTestAccount
        } else if Self.debug && arguments.contains("--log-out") {
            self = .logOut
        } else if Self.debug && arguments.contains("--notification-status") {
            self = .notificationStatus
        } else if Self.debug && arguments.contains("--render-window") {
            self = .renderWindow
        } else if Self.debug, let index = arguments.firstIndex(of: "--settings") {
            self = .settings(arguments.indices.contains(index + 1) ? arguments[index + 1] : nil)
        } else if Self.debug, let index = arguments.firstIndex(of: "--debug-dumps"),
            arguments.indices.contains(index + 1)
        {
            self = .debugDumps(arguments[index + 1])
        } else {
            return nil
        }
    }

    private static var debug: Bool {
        #if DEBUG
            return true
        #else
            return false
        #endif
    }

    func runAndExit() -> Never {
        if case .renderWindow = self {
            // AppKit needs the main thread, which dispatchMain below gives up to the main queue's workers.
            exit(MainActor.assumeIsolated { DebugCommands.renderWindow() } ? 0 : 1)
        }
        Task {
            let passed: Bool
            switch self {
            case .checkStorage:
                passed = StorageCheckReport.run()
            case .checkConnection:
                let report = await ConnectionCheck.runWithSharedStorage()
                print(report.text)
                passed = report.passed
            case .checkFromMail:
                passed = await Self.checkFromMail()
            case .useTestAccount:
                passed = await Self.useTestAccount()
            case .logOut:
                passed = await Self.logOut()
            case .settings(let json):
                passed = DebugCommands.settings(json)
            case .debugDumps(let action):
                passed = DebugCommands.debugDumps(action)
            case .renderWindow:
                passed = false
            case .notificationStatus:
                passed = await DebugCommands.notificationStatus()
            }
            exit(passed ? 0 : 1)
        }
        dispatchMain()
    }

    private static func fail(_ text: String) -> Bool {
        FileHandle.standardError.write(Data("error: \(text)\n".utf8))
        return false
    }

    private static func checkFromMail() async -> Bool {
        guard let group = SharedStorage.appGroupIdentifier, let mailCheck = MailCheck(groupIdentifier: group) else {
            return fail("no App Group container")
        }
        do {
            guard let answer = try await mailCheck.askInMail() else {
                return fail(MailCheck.noAnswer)
            }
            print("Checked by the extension in Mail:\n\(answer.report.text)")
            return answer.report.passed
        } catch {
            return fail(error.localizedDescription)
        }
    }

    private static func useTestAccount() async -> Bool {
        let environment = ProcessInfo.processInfo.environment
        guard let address = environment["NCME_TEST_SERVER_URL"], let login = environment["NCME_TEST_USERNAME"],
            let password = environment["NCME_TEST_PASSWORD"], let directory = environment["NCME_TEST_DIRECTORY"]
        else {
            return fail("the NCME_TEST_ variables aren't set. Run this through scripts/use-test-account.sh.")
        }
        guard let group = SharedStorage.appGroupIdentifier, let store = SettingsStore(groupIdentifier: group) else {
            return fail("no App Group identifier in Info.plist")
        }
        do {
            let server = try ServerAddress.url(from: address)
            let account = try await NextcloudClient.appPassword(server: server, loginName: login, password: password)
            try Credentials(group: group).save(account)
            var settings = store.load()
            settings.server = server.absoluteString
            settings.directory = directory
            store.save(settings)
            print("Stored an app password for \(login) on \(server.absoluteString), with the directory \(directory).")
            return true
        } catch {
            return fail(error.localizedDescription)
        }
    }

    private static func logOut() async -> Bool {
        guard let group = SharedStorage.appGroupIdentifier else {
            return fail("no App Group identifier in Info.plist")
        }
        let credentials = Credentials(group: group)
        do {
            guard let account = try credentials.load() else {
                print("Not logged in.")
                return true
            }
            try await NextcloudClient(account: account, userID: account.loginName).revokeAppPassword()
            try credentials.delete()
            print("Revoked and deleted the app password for \(account.loginName).")
            return true
        } catch {
            return fail(error.localizedDescription)
        }
    }
}

/// Runs the storage check and prints it.
enum StorageCheckReport {
    /// Writes a fresh value to every kind of shared storage, so the extension can read it back.
    static func check() -> (identifier: String?, result: StorageCheck.Result?) {
        guard let identifier = SharedStorage.appGroupIdentifier else {
            return (nil, nil)
        }
        let value = "written by the host app at \(ISO8601DateFormatter().string(from: Date()))"
        return (identifier, StorageCheck(groupIdentifier: identifier).write(value))
    }

    static func run() -> Bool {
        let (identifier, result) = check()
        guard let identifier, let result else {
            FileHandle.standardError.write(Data("error: no App Group identifier in Info.plist\n".utf8))
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(result)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        print("App Group: \(identifier)\n\(json)\npassed: \(result.passed)")
        return result.passed
    }
}
