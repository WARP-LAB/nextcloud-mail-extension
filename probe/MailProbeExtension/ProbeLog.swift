import Foundation
import MailKit
import os

/// Writes each event to the unified log and to `events.jsonl` in the extension's container.
enum ProbeLog {
    private static let logger = Logger(subsystem: "lv.warp.mailprobe", category: "probe")
    private static let lock = NSLock()

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("MailProbe", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func event(_ name: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = name
        record["pid"] = Int(ProcessInfo.processInfo.processIdentifier)
        record["time"] = ISO8601DateFormatter.probe.string(from: Date())
        guard let json = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }

        logger.notice("\(String(decoding: json, as: UTF8.self), privacy: .public)")

        lock.lock()
        defer { lock.unlock() }
        let url = directory.appendingPathComponent("events.jsonl")
        guard let handle = try? FileHandle(forWritingTo: url) else {
            try? (json + Data("\n".utf8)).write(to: url)
            return
        }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: json + Data("\n".utf8))
    }

    /// Prefixed with the process ID because sequence numbers restart if the extension is relaunched.
    static func dump(_ data: Data, named name: String) {
        try? data.write(to: directory.appendingPathComponent("\(ProcessInfo.processInfo.processIdentifier)-\(name)"))
    }
}

extension ISO8601DateFormatter {
    fileprivate static let probe: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

/// Message metadata that is safe to log for any message: no subjects, addresses or content.
func contextFields(_ message: MEMessage, _ context: MEComposeContext) -> [String: Any] {
    [
        "contextID": context.contextID.uuidString,
        "action": context.action.rawValue,
        "state": message.state.rawValue,
        "shouldSign": context.shouldSign,
        "shouldEncrypt": context.shouldEncrypt,
        "isSigned": context.isSigned,
        "isEncrypted": context.isEncrypted,
        "rawBytes": message.rawData?.count ?? -1,
    ]
}
