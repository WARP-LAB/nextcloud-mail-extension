import Foundation

/// Checks the account and the settings against the server, for the host app's Test connection. The host app runs it
/// itself, and asks the extension to run it inside Mail (R17, R18).
enum ConnectionCheck {
    struct Report: Codable, Equatable {
        var passed: Bool
        var lines: [String]

        var text: String {
            lines.joined(separator: "\n")
        }

        static func failed(_ line: String) -> Report {
            Report(passed: false, lines: [line])
        }
    }

    /// The oldest Nextcloud version the extension is made for (NFR1).
    static let oldestVersion = 34

    static func run(settings: Settings, account: NextcloudAccount?) async -> Report {
        guard let account else {
            return .failed("Not logged in to Nextcloud. Log in in NextcloudAppleMail.")
        }
        var lines: [String] = []
        do {
            let client = try await NextcloudClient.connect(account)
            let host = account.server.host ?? account.server.absoluteString
            lines.append("Logged in to \(host) as \(account.loginName).")
            let limits = try await client.sharingLimits()
            var passed = true
            if let major = Int(limits.version.prefix { $0 != "." }), major < oldestVersion {
                lines.append(
                    "Nextcloud \(limits.version). NextcloudAppleMail needs Nextcloud \(oldestVersion) or later.")
                passed = false
            } else {
                lines.append("Nextcloud \(limits.version).")
            }
            lines += notes(on: limits)
            let directory = settings.uploadDirectory
            if try await client.exists(directory) {
                lines.append("The upload directory “\(directory)” exists.")
            } else {
                lines.append("The upload directory “\(directory)” doesn't exist yet. The first send creates it.")
            }
            return Report(passed: passed, lines: lines)
        } catch {
            return Report(passed: false, lines: lines + [error.localizedDescription])
        }
    }

    /// Runs the check with the settings and the account in the App Group and the shared Keychain item, as the
    /// process running it sees them.
    static func runWithSharedStorage() async -> Report {
        guard let group = SharedStorage.appGroupIdentifier, let store = SettingsStore(groupIdentifier: group) else {
            return .failed("No App Group identifier in Info.plist.")
        }
        let account: NextcloudAccount?
        do {
            account = try Credentials(group: group).load()
        } catch {
            return .failed("The app password couldn't be read. \(error.localizedDescription)")
        }
        return await run(settings: store.load(), account: account)
    }

    /// What the server's rules mean for the links (FR4, FR7).
    static func notes(on limits: SharingLimits) -> [String] {
        var lines: [String] = []
        if limits.passwordEnforced {
            lines.append("The server requires a password on links, so set one in each message window before sending.")
        }
        if limits.expiryEnforced, let days = limits.defaultExpiryDays {
            lines.append("The server lets links last at most \(days) days, so links expire after \(days) days at most.")
        }
        return lines
    }
}

/// The host app's request for the extension to run the connection check inside Mail, and the extension's answer, as
/// files in the App Group's container. The extension answers when a message window opens.
struct MailCheck {
    struct Request: Codable, Equatable {
        var id: UUID
        var date: Date
    }

    struct Answer: Codable, Equatable {
        var id: UUID
        var date: Date
        var report: ConnectionCheck.Report
    }

    /// A request older than this is ignored, so that a message window opened later doesn't run the check.
    static let lifetime: TimeInterval = 120

    let container: URL

    init(container: URL) {
        self.container = container
    }

    init?(groupIdentifier: String) {
        guard
            let container = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: groupIdentifier)
        else {
            return nil
        }
        self.container = container
    }

    private var requestURL: URL {
        container.appendingPathComponent("mail-check-request.json")
    }

    private var answerURL: URL {
        container.appendingPathComponent("mail-check-answer.json")
    }

    /// Asks for a new check, replacing any earlier request and answer.
    func request(now: Date = Date()) throws -> Request {
        let request = Request(id: UUID(), date: now)
        try? FileManager.default.removeItem(at: answerURL)
        try write(request, to: requestURL)
        return request
    }

    /// The request still waiting for an answer, if there's one and it isn't too old.
    func pendingRequest(now: Date = Date()) -> Request? {
        guard let request = read(Request.self, from: requestURL),
            now.timeIntervalSince(request.date) < Self.lifetime,
            read(Answer.self, from: answerURL)?.id != request.id
        else {
            return nil
        }
        return request
    }

    func answer(_ request: Request, with report: ConnectionCheck.Report, now: Date = Date()) throws {
        try write(Answer(id: request.id, date: now, report: report), to: answerURL)
    }

    /// The extension's answer to the request, once it's there.
    func answer(to request: Request) -> Answer? {
        guard let answer = read(Answer.self, from: answerURL), answer.id == request.id else {
            return nil
        }
        return answer
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? Data(contentsOf: url)).flatMap { try? decoder.decode(T.self, from: $0) }
    }
}
