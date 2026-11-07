import Foundation

/// Where the host app and the extension share settings and secrets: their App Group.
///
/// The group's identifier comes from the Info.plist key `NCMEAppGroupIdentifier`. The build sets it to the team ID
/// followed by `lv.warp.nextcloudmailextension`, so the team ID never appears in tracked files.
enum SharedStorage {
    static let infoKey = "NCMEAppGroupIdentifier"

    /// The App Group identifier in an Info.plist dictionary, or nil if it's missing, empty or wasn't expanded.
    static func appGroupIdentifier(in info: [String: Any]?) -> String? {
        guard let value = info?[infoKey] as? String, !value.isEmpty, !value.contains("$(") else {
            return nil
        }
        return value
    }

    /// The running app's or extension's App Group identifier.
    static var appGroupIdentifier: String? {
        appGroupIdentifier(in: Bundle.main.infoDictionary)
    }
}
