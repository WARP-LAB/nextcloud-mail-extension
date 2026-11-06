import Foundation
import Security

/// Checks that the App Group's container, its settings and a Keychain item in the group all work.
///
/// The host app writes a value to all three, and the extension reads them back. This is task T1's test of whether
/// the free Personal Team's signing allows sharing at all (docs/RISKS.md, R17).
struct StorageCheck {
    /// What happened to each kind of storage: "ok: <value>" or "failed: <reason>".
    struct Result: Codable, Equatable {
        var container: String
        var settings: String
        var keychain: String

        var passed: Bool {
            [container, settings, keychain].allSatisfy { $0.hasPrefix("ok") }
        }
    }

    static let settingsKey = "storageCheck"
    static let fileName = "storage-check.txt"
    static let keychainService = "lv.warp.nextcloudapplemail.storage-check"
    static let keychainAccount = "storage-check"

    let groupIdentifier: String

    /// Writes `value` to the container, the settings and the Keychain, then reads each back.
    func write(_ value: String) -> Result {
        Result(
            container: writeContainer(value),
            settings: writeSettings(value),
            keychain: writeKeychain(value)
        )
    }

    /// Reads the values that `write(_:)` stored.
    func read() -> Result {
        Result(container: readContainer(), settings: readSettings(), keychain: readKeychain())
    }

    // MARK: - Container

    private var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appendingPathComponent(Self.fileName)
    }

    private func writeContainer(_ value: String) -> String {
        guard let url = fileURL else {
            return "failed: no container for \(groupIdentifier)"
        }
        do {
            try Data(value.utf8).write(to: url, options: .atomic)
        } catch {
            return "failed: \(error.localizedDescription)"
        }
        return readContainer()
    }

    private func readContainer() -> String {
        guard let url = fileURL else {
            return "failed: no container for \(groupIdentifier)"
        }
        guard let data = try? Data(contentsOf: url) else {
            return "failed: nothing written yet"
        }
        return "ok: \(Self.text(data))"
    }

    // MARK: - Settings

    private func writeSettings(_ value: String) -> String {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            return "failed: no settings for \(groupIdentifier)"
        }
        defaults.set(value, forKey: Self.settingsKey)
        return readSettings()
    }

    private func readSettings() -> String {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            return "failed: no settings for \(groupIdentifier)"
        }
        guard let value = defaults.string(forKey: Self.settingsKey) else {
            return "failed: nothing written yet"
        }
        return "ok: \(value)"
    }

    // MARK: - Keychain

    private var keychainQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainService,
            kSecAttrAccount as String: Self.keychainAccount,
            kSecAttrAccessGroup as String: groupIdentifier,
            kSecUseDataProtectionKeychain as String: true,
        ]
    }

    private func writeKeychain(_ value: String) -> String {
        SecItemDelete(keychainQuery as CFDictionary)
        var item = keychainQuery
        item[kSecValueData as String] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else {
            return "failed: \(Self.message(for: status))"
        }
        return readKeychain()
    }

    private func readKeychain() -> String {
        var query = keychainQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return "failed: \(Self.message(for: status))"
        }
        return "ok: \(Self.text(data))"
    }

    private static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? "<not UTF-8>"
    }

    private static func message(for status: OSStatus) -> String {
        let text = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "\(text) (\(status))"
    }
}
