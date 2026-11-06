import Foundation

/// What a send call gives back to Mail.
enum SendResult: Equatable {
    /// Mail sends the message as it is.
    case unchanged
    case rewritten(Data)
    /// Stops the send, with this text in Mail's alert.
    case failed(String)
}

/// Runs Mail's `encode()` calls one at a time, with each message's uploads in the ledger (docs/ARCHITECTURE.md,
/// "Send flow"). Mail's first send call uploads, and its second finds everything in the ledger.
actor Sender {
    struct Dependencies {
        var settings: () -> Settings
        /// A client for the logged-in account, or nil when nobody is logged in.
        var connect: () async throws -> NextcloudService?
        var store: UploadLedgerStore?
        var now: () -> Date = Date.init
        var temporaryDirectory = FileManager.default.temporaryDirectory
    }

    /// After a failed send call, the next one for the message fails the same way, within this time (docs/MAIL.md,
    /// "Failed uploads").
    static let failureLifetime: TimeInterval = 60

    private struct Failure {
        var text: String
        var date: Date
    }

    private let dependencies: Dependencies
    private var ledger: UploadLedger
    private var failures: [String: Failure] = [:]
    /// Messages with a call running, and the calls waiting for it. An actor runs other calls while one waits for
    /// the network, so calls for the same message are queued here.
    private var busy = Set<String>()
    private var waiting: [String: [CheckedContinuation<Void, Never>]] = [:]

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        ledger = dependencies.store?.load() ?? UploadLedger()
    }

    /// One `encode()` call. `messageID` is Mail's `X-Universally-Unique-Identifier`, found in the message, with
    /// `contextID` as a fallback.
    func encode(_ raw: Data?, isAutoSave: Bool, contextID: UUID) async -> SendResult {
        // Auto-saves keep their files (D3, docs/MAIL.md).
        guard let raw, !isAutoSave else {
            return .unchanged
        }
        let message = MimeMessage(raw)
        let messageID = message.root.field("x-universally-unique-identifier") ?? contextID.uuidString
        await lock(messageID)
        defer {
            unlock(messageID)
        }
        if let failure = failures.removeValue(forKey: messageID),
            dependencies.now().timeIntervalSince(failure.date) < Self.failureLifetime
        {
            return .failed(failure.text)
        }
        do {
            guard let data = try await send(message, messageID: messageID) else {
                return .unchanged
            }
            return .rewritten(data)
        } catch {
            let text = error.localizedDescription
            failures[messageID] = Failure(text: text, date: dependencies.now())
            return .failed(text)
        }
    }

    private func send(_ message: MimeMessage, messageID: String) async throws -> Data? {
        var entry = ledger.entries[messageID] ?? UploadLedger.Entry(updated: dependencies.now())
        let signature = LinkPolicy.signatureContentIDs(in: message)
        entry.signatureContentIDs = Array(Set(entry.signatureContentIDs).union(signature)).sorted()
        let settings = dependencies.settings()
        let files = settings.linkPolicy.linkedFiles(in: message, signatureContentIDs: Set(entry.signatureContentIDs))

        // Mail Drop: its message has the header, and the call before it has none of the files (FR10, docs/MAIL.md).
        if message.root.field("remote-attachment-url") != nil || (files.isEmpty && entry.hasUploads) {
            if entry.hasUploads, let service = try? await dependencies.connect() {
                let flow = SendFlow(settings: settings, service: service)
                try? await flow.removeUploads(entry)
            }
            store(nil, for: messageID)
            return nil
        }
        guard !files.isEmpty else {
            if !signature.isEmpty {
                store(entry, for: messageID)
            }
            return nil
        }
        guard let service = try await connect() else {
            throw SendError.notSetUp
        }
        let record = MessageRecord(entry)
        defer {
            store(record.entry, for: messageID)
        }
        var flow = SendFlow(settings: settings, service: service)
        flow.today = dependencies.now()
        flow.temporaryDirectory = dependencies.temporaryDirectory
        return try await flow.run(message, files: files, password: nil, record: record)
    }

    private func lock(_ messageID: String) async {
        while busy.contains(messageID) {
            await withCheckedContinuation { waiting[messageID, default: []].append($0) }
        }
        busy.insert(messageID)
    }

    private func unlock(_ messageID: String) {
        busy.remove(messageID)
        for waiter in waiting.removeValue(forKey: messageID) ?? [] {
            waiter.resume()
        }
    }

    private func connect() async throws -> NextcloudService? {
        do {
            return try await dependencies.connect()
        } catch let error as KeychainError {
            throw SendError("NextcloudAppleMail couldn't read its app password. \(error.localizedDescription)")
        }
    }

    /// Keeps the entry, or drops it for nil, and saves the ledger. If saving fails, the entry is still kept here,
    /// which covers Mail's second call.
    private func store(_ entry: UploadLedger.Entry?, for messageID: String) {
        var entry = entry
        entry?.updated = dependencies.now()
        ledger.entries[messageID] = entry
        try? dependencies.store?.save(ledger, now: dependencies.now())
    }
}
