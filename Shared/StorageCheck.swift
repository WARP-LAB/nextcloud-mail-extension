import Foundation

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
    static let keychainService = "lv.warp.nextcloudmailextension.storage-check"
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

    private func writeKeychain(_ value: String) -> String {
        do {
            try Keychain.write(
                Data(value.utf8), service: Self.keychainService, account: Self.keychainAccount, group: groupIdentifier)
        } catch {
            return "failed: \(error.localizedDescription)"
        }
        return readKeychain()
    }

    private func readKeychain() -> String {
        do {
            guard
                let data = try Keychain.read(
                    service: Self.keychainService, account: Self.keychainAccount, group: groupIdentifier)
            else {
                return "failed: nothing written yet"
            }
            return "ok: \(Self.text(data))"
        } catch {
            return "failed: \(error.localizedDescription)"
        }
    }

    private static func text(_ data: Data) -> String {
        String(bytes: data, encoding: .utf8) ?? "<not UTF-8>"
    }
}
