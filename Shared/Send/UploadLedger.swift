import CryptoKit
import Foundation

/// What has been uploaded and shared for each message, so that Mail's second send call, a retry after a failure and
/// a send after Undo Send reuse it (docs/ARCHITECTURE.md, "Upload ledger"). It never holds passwords.
struct UploadLedger: Codable, Equatable {
    struct StoredFile: Codable, Equatable {
        /// The file's path on Nextcloud, whose last name is the file's name there.
        var path: String
        /// The file's own share, with a link for each file (D17).
        var share: Share?

        var name: String {
            NextcloudClient.names(in: path).last ?? path
        }
    }

    struct Entry: Codable, Equatable {
        var folder: String?
        var folderShare: Share?
        /// By the SHA-256 of the decoded file, in hex.
        var files: [String: StoredFile] = [:]
        /// The Content-IDs of the signature's images, which only the first send call's HTML marks (docs/MAIL.md).
        var signatureContentIDs: [String] = []
        var updated: Date

        init(updated: Date) {
            self.updated = updated
        }

        /// Whether anything is on Nextcloud for the message.
        var hasUploads: Bool {
            folder != nil
        }
    }

    /// Entries not used for this long are dropped.
    static let lifetime: TimeInterval = 30 * 24 * 60 * 60

    /// By message ID, Mail's `X-Universally-Unique-Identifier`.
    var entries: [String: Entry] = [:]

    mutating func prune(now: Date) {
        entries = entries.filter { now.timeIntervalSince($0.value.updated) < Self.lifetime }
    }

    /// The key a file is stored under.
    static func key(for data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Reads and writes the ledger as a JSON file.
struct UploadLedgerStore {
    let url: URL

    /// `upload-ledger.json` in the running extension's own container.
    static var inContainer: UploadLedgerStore? {
        guard
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        else {
            return nil
        }
        return UploadLedgerStore(url: support.appendingPathComponent("upload-ledger.json"))
    }

    /// The ledger, or an empty one if there's none or it can't be read.
    func load() -> UploadLedger {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url), let ledger = try? decoder.decode(UploadLedger.self, from: data)
        else {
            return UploadLedger()
        }
        return ledger
    }

    /// Saves the ledger, after dropping old entries.
    func save(_ ledger: UploadLedger, now: Date = Date()) throws {
        var ledger = ledger
        ledger.prune(now: now)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder.encode(ledger).write(to: url, options: .atomic)
    }

    /// Changes one message's entry and saves the ledger at once, so a failure part way keeps what's done.
    func update(_ messageID: String, now: Date = Date(), _ change: (inout UploadLedger.Entry) -> Void) throws {
        var ledger = load()
        var entry = ledger.entries[messageID] ?? UploadLedger.Entry(updated: now)
        change(&entry)
        entry.updated = now
        ledger.entries[messageID] = entry
        try save(ledger, now: now)
    }

    func remove(_ messageID: String) throws {
        var ledger = load()
        ledger.entries[messageID] = nil
        try save(ledger)
    }
}
