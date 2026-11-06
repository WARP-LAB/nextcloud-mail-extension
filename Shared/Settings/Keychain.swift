import Foundation
import Security

/// A Keychain error, with the system's text for its status.
struct KeychainError: Error, Equatable, LocalizedError {
    let status: OSStatus

    var errorDescription: String? {
        "The Keychain refused: \(Keychain.message(for: status))"
    }
}

/// Generic password items in the Keychain group that the host app and the extension share (D16).
enum Keychain {
    /// The item's data, or nil if there's no item.
    static func read(service: String, account: String, group: String) throws -> Data? {
        var query = self.query(service, account, group)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return data
    }

    /// Stores the data, replacing the item's data if it exists. The item stays on this Mac.
    static func write(_ data: Data, service: String, account: String, group: String) throws {
        let query = self.query(service, account, group)
        let update = [kSecValueData as String: data]
        var status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            status = SecItemAdd(item as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError(status: status)
        }
    }

    /// Deletes the item. Deleting one that doesn't exist isn't an error.
    static func delete(service: String, account: String, group: String) throws {
        let status = SecItemDelete(query(service, account, group) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    static func message(for status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(text) (\(status))"
    }

    private static func query(_ service: String, _ account: String, _ group: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: group,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }
}

/// The Nextcloud account, app password included, in the shared Keychain item. Nothing else stores it (NFR2).
struct Credentials {
    static let service = "lv.warp.nextcloudapplemail.account"
    static let account = "nextcloud"

    /// The Keychain group, which has the same identifier as the App Group (D16).
    let group: String

    /// The account, or nil when nobody is logged in.
    func load() throws -> NextcloudAccount? {
        guard let data = try Keychain.read(service: Self.service, account: Self.account, group: group) else {
            return nil
        }
        return try JSONDecoder().decode(NextcloudAccount.self, from: data)
    }

    func save(_ account: NextcloudAccount) throws {
        let data = try JSONEncoder().encode(account)
        try Keychain.write(data, service: Self.service, account: Self.account, group: group)
    }

    func delete() throws {
        try Keychain.delete(service: Self.service, account: Self.account, group: group)
    }
}
