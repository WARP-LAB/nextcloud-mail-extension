import Foundation

/// Debug builds only: copies of what Mail passes `encode()`, so that the Mail checks can see each call's message
/// (docs/TESTING.md). They're made only while turned on, and only for messages whose subject has `[ncam`, so other
/// mail is never copied. They stay in the App Group's container until taken, which deletes them.
enum DebugDumps {
    struct Dump: Equatable {
        var name: String
        var data: Data
    }

    static let settingsKey = "debugDumps"
    static let marker = "[ncam"

    static func isOn(group: String) -> Bool {
        UserDefaults(suiteName: group)?.bool(forKey: settingsKey) ?? false
    }

    static func turn(on isOn: Bool, group: String) {
        UserDefaults(suiteName: group)?.set(isOn, forKey: settingsKey)
    }

    static func directory(group: String) -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("debug-dumps")
    }

    /// Whether a message is one of the checks' test messages, by the marker in its subject.
    static func isTestMessage(_ raw: Data) -> Bool {
        let subject = MimeMessage(raw).root.field("subject").map(EncodedWords.decode) ?? ""
        return subject.contains(marker)
    }

    static func save(_ raw: Data, isAutoSave: Bool, group: String, now: Date = Date()) {
        guard isOn(group: group), isTestMessage(raw), let directory = directory(group: group) else {
            return
        }
        let stamp = now.formatted(
            .iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: true)
                .timeSeparator(.omitted))
        let name = "\(stamp)-\(UUID().uuidString.prefix(4))-\(isAutoSave ? "autosave" : "send").eml"
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? raw.write(to: directory.appendingPathComponent(name), options: .atomic)
    }

    /// The dumps, oldest first, deleted as they're read.
    static func take(group: String) -> [Dump] {
        guard let directory = directory(group: group),
            let names = try? FileManager.default.contentsOfDirectory(atPath: directory.path)
        else {
            return []
        }
        return names.filter { $0.hasSuffix(".eml") }.sorted().compactMap { name in
            let url = directory.appendingPathComponent(name)
            defer {
                try? FileManager.default.removeItem(at: url)
            }
            return (try? Data(contentsOf: url)).map { Dump(name: name, data: $0) }
        }
    }
}
