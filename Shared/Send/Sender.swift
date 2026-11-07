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
        /// The passwords typed in the toolbar popover (FR7), or nil for none.
        var passwords: MessageValues?
        /// Each email's own link expiry from the popover, as `LinkExpiry` JSON, or nil for none.
        var expiries: MessageValues?
        /// Each email's `LinkChoice` from the popover, or nil for none.
        var linkChoices: MessageValues?
        /// Told, with the message ID, when uploads start and end (R3).
        var progress: (String, SendProgress) -> Void = { _, _ in }
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
    /// The password each message's shares were last given in this process, "" for none (`SendFlow.run`).
    private var applied: [String: String] = [:]

    init(_ dependencies: Dependencies) {
        self.dependencies = dependencies
        ledger = dependencies.store?.load() ?? UploadLedger()
        dependencies.passwords?.prune(now: dependencies.now())
        dependencies.expiries?.prune(now: dependencies.now())
        dependencies.linkChoices?.prune(now: dependencies.now())
    }

    /// One `encode()` call. `messageID` is Mail's `X-Universally-Unique-Identifier`, found in the message, with
    /// `contextID` as a fallback.
    func encode(_ raw: Data?, isAutoSave: Bool, contextID: UUID) async -> SendResult {
        guard let raw else {
            return .unchanged
        }
        // Every call, an auto-save too, links its context to the message ID, so that a reopened draft, which gets a
        // new context, finds the password typed in the old one (docs/MAIL.md).
        let headerID = MimePart.headerField("x-universally-unique-identifier", in: raw)
        if let headerID {
            dependencies.passwords?.link(context: contextID, message: headerID)
            dependencies.expiries?.link(context: contextID, message: headerID)
            dependencies.linkChoices?.link(context: contextID, message: headerID)
        }
        // Auto-saves keep their files (D3, docs/MAIL.md).
        guard !isAutoSave else {
            return .unchanged
        }
        let message = MimeMessage(raw)
        let messageID = headerID ?? contextID.uuidString
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
            guard let data = try await send(message, messageID: messageID, contextID: contextID) else {
                return .unchanged
            }
            return .rewritten(data)
        } catch {
            let text = Self.alertText(for: error)
            failures[messageID] = Failure(text: text, date: dependencies.now())
            return .failed(text)
        }
    }

    private func send(_ message: MimeMessage, messageID: String, contextID: UUID) async throws -> Data? {
        var entry = ledger.entries[messageID] ?? UploadLedger.Entry(updated: dependencies.now())
        let signature = LinkPolicy.signatureContentIDs(in: message)
        entry.signatureContentIDs = Array(Set(entry.signatureContentIDs).union(signature)).sorted()
        let signatureIDs = Set(entry.signatureContentIDs)
        let signatureFiles = message.files.filter {
            $0.contentID.map { signatureIDs.contains($0.lowercased()) } ?? false
        }
        entry.signatureFiles = Array(
            Set(entry.signatureFiles).union(signatureFiles.map { UploadLedger.key(for: $0.data) })
        )
        .sorted()
        let settings = dependencies.settings()
        let known = Set(entry.signatureFiles)
        let choice = LinkChoice(stored: dependencies.linkChoices?.value(context: contextID, message: messageID))
        let policy = settings.linkPolicy(for: choice)
        let files = policy.linkedFiles(in: message, signatureContentIDs: signatureIDs) { file in
            file.contentType.hasPrefix("image/") && known.contains(UploadLedger.key(for: file.data))
        }

        // Mail Drop: its message has the header, and the call before it has none of the files (FR10, docs/MAIL.md).
        // Files kept attached after Undo Send also leave nothing to link, but the email's popover values stay.
        if message.root.field("remote-attachment-url") != nil || (files.isEmpty && entry.hasUploads) {
            await removeUploads(entry, settings, messageID, forgetValues: choice != .keepAttached)
            return nil
        }
        guard !files.isEmpty else {
            if !signature.isEmpty || !signatureFiles.isEmpty {
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
        let report = dependencies.progress
        flow.progress = { report(messageID, $0) }
        let password = dependencies.passwords?.value(context: contextID, message: messageID)
        let expiry = dependencies.expiries?.value(context: contextID, message: messageID).flatMap {
            try? JSONDecoder().decode(LinkExpiry.self, from: Data($0.utf8))
        }
        let data = try await flow.run(
            message, files: files, password: password, applied: applied[messageID], expiry: expiry, record: record)
        applied[messageID] = password ?? ""
        return data
    }

    /// Deletes what was uploaded for the message and its entry, and with `forgetValues` the popover's values for
    /// it, after Mail Drop took over (D8).
    private func removeUploads(
        _ entry: UploadLedger.Entry, _ settings: Settings, _ messageID: String, forgetValues: Bool
    ) async {
        if entry.hasUploads {
            if let service = try? await dependencies.connect() {
                try? await SendFlow(settings: settings, service: service).removeUploads(entry)
            }
            if forgetValues {
                dependencies.passwords?.forget(message: messageID)
                dependencies.expiries?.forget(message: messageID)
                dependencies.linkChoices?.forget(message: messageID)
            }
            applied[messageID] = nil
        }
        store(nil, for: messageID)
    }

    /// What Mail's alert says: the error, and how to send anyway when the server or the network is unavailable (T21).
    static func alertText(for error: Error) -> String {
        let text = error.localizedDescription
        guard (error as? NextcloudError)?.serverUnavailable == true else {
            return text
        }
        return text + " " + SendError.sendAttachedHint
    }

    /// How many files the send calls turned into links for the message, for FR6's check.
    func linkedFiles(messageID: String) -> Int {
        ledger.entries[messageID]?.files.count ?? 0
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
            throw SendError("NextcloudMailExtension couldn't read its app password. \(error.localizedDescription)")
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
