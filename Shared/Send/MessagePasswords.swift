import Foundation

/// Where `MessagePasswords` keeps a copy of each email's password, so that tests can keep it in memory.
protocol PasswordVault {
    func read(_ messageID: String) throws -> String?
    func write(_ password: String, for messageID: String) throws
    func delete(_ messageID: String) throws
    /// The message IDs of copies not changed since this date.
    func unchanged(since date: Date) throws -> [String]
}

/// The Keychain items of the shared group, one per message ID (R8).
struct KeychainPasswordVault: PasswordVault {
    static let service = "lv.warp.nextcloudapplemail.message-password"

    let group: String

    func read(_ messageID: String) throws -> String? {
        try Keychain.read(service: Self.service, account: messageID, group: group).flatMap {
            String(bytes: $0, encoding: .utf8)
        }
    }

    func write(_ password: String, for messageID: String) throws {
        try Keychain.write(Data(password.utf8), service: Self.service, account: messageID, group: group)
    }

    func delete(_ messageID: String) throws {
        try Keychain.delete(service: Self.service, account: messageID, group: group)
    }

    func unchanged(since date: Date) throws -> [String] {
        try Keychain.items(service: Self.service, group: group).filter { $0.modified < date }.map(\.account)
    }
}

/// The password typed for each email in the toolbar popover (FR7, docs/ARCHITECTURE.md).
///
/// The popover knows only the compose context, and `encode()` knows the context and the message ID. A reopened draft
/// gets a new context but keeps its message ID, so every `encode()` call, auto-saves included, links its context to
/// the message ID, and the password is also kept in the Keychain under the message ID, which survives Mail
/// restarting (R8, docs/MAIL.md). A password is never logged, and never written anywhere else.
final class MessagePasswords: @unchecked Sendable {
    static let shared = MessagePasswords(vault: SharedStorage.appGroupIdentifier.map(KeychainPasswordVault.init))

    private let lock = NSLock()
    private let vault: PasswordVault?
    /// What was typed in each context. An empty string means the password was cleared there.
    private var typed: [UUID: String] = [:]
    private var messageOfContext: [UUID: String] = [:]

    init(vault: PasswordVault?) {
        self.vault = vault
    }

    /// The popover's field, at each change.
    func set(_ password: String, context: UUID) {
        lock.lock()
        defer { lock.unlock() }
        typed[context] = password
        if let message = messageOfContext[context] {
            keep(password, for: message)
        }
    }

    /// Each `encode()` call, and a compose session that already knows its message ID.
    func link(context: UUID, message: String) {
        lock.lock()
        defer { lock.unlock() }
        messageOfContext[context] = message
        if let password = typed[context] {
            keep(password, for: message)
        }
    }

    /// The email's password, or nil for none: typed in this context, else in another context of the same message,
    /// else kept in the Keychain.
    func password(context: UUID, message: String?) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return find(context: context, message: message ?? messageOfContext[context]).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// What the popover shows when it opens.
    func shown(context: UUID) -> String {
        password(context: context, message: nil) ?? ""
    }

    /// Deletes the copies of passwords that weren't changed for as long as the ledger keeps a message, so that they
    /// go with the message's entry (docs/ARCHITECTURE.md).
    func prune(now: Date = Date()) {
        let oldest = now.addingTimeInterval(-UploadLedger.lifetime)
        for message in (try? vault?.unchanged(since: oldest)) ?? [] {
            try? vault?.delete(message)
        }
    }

    /// Forgets the message's password, as when Mail Drop sent it without links.
    func forget(message: String) {
        lock.lock()
        defer { lock.unlock() }
        for (context, linked) in messageOfContext where linked == message {
            typed[context] = nil
            messageOfContext[context] = nil
        }
        try? vault?.delete(message)
    }

    private func find(context: UUID, message: String?) -> String? {
        if let password = typed[context] {
            return password
        }
        guard let message else {
            return nil
        }
        for (other, linked) in messageOfContext where linked == message {
            if let password = typed[other] {
                return password
            }
        }
        return try? vault?.read(message)
    }

    private func keep(_ password: String, for message: String) {
        if password.isEmpty {
            try? vault?.delete(message)
        } else {
            try? vault?.write(password, for: message)
        }
    }
}
