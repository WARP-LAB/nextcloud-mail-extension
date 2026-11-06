import Foundation

/// The user's settings (FR2–FR6, FR8, FR9, D17). The host app writes them to the App Group, and the extension reads
/// them there each time it needs them.
struct Settings: Equatable {
    /// How an email's files are shared on Nextcloud (D17).
    enum Sharing: String, Codable, CaseIterable {
        /// One share per email, of its folder. The default.
        case folder
        /// A share per file, and one for the folder when FR9 applies.
        case eachFile
    }

    /// Where the links go when the email's folder is shared (FR8, D17).
    enum Placement: String, Codable, CaseIterable {
        /// Each file's links where the file was. The default.
        case whereEachFileWas
        /// Only the folder's links, after the user's own text, with the files' names listed above them.
        case folderLinksOnly
    }

    static let defaultDirectory = "Mail attachments"

    /// The server address the user typed to log in. Requests use the server that the login returned.
    var server = ""
    /// The directory on Nextcloud where each email gets its own folder (FR2).
    var directory = Settings.defaultDirectory
    /// FR3: true when only files over `sizeLimitMegabytes` become links, false when all files do.
    var onlyLargeFiles = false
    var sizeLimitMegabytes = 10.0
    var pastedImagesBecomeLinks = true
    var expiry = LinkExpiry.month
    /// FR5.
    var warnIfSignOff = true
    /// FR6. Empty means no check.
    var warningPhrases: [String] = []
    var sharing = Sharing.folder
    var placement = Placement.whereEachFileWas
    /// FR8.
    var linkStyle = LinkText.Style.viewAndDownload
    /// FR9.
    var folderLinks = false

    /// The directory without spaces, slashes and `.` or `..` names, or the default when that leaves nothing.
    var uploadDirectory: String {
        let names = directory.split(separator: "/")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
        return names.isEmpty ? Self.defaultDirectory : names.joined(separator: "/")
    }

    /// FR3's rule. Sizes are decimal, as Finder and the link text show them: 1 MB is 1,000,000 bytes.
    var linkPolicy: LinkPolicy {
        let rule: LinkPolicy.Rule =
            onlyLargeFiles ? .largerThan(bytes: Int(max(0, sizeLimitMegabytes) * 1_000_000)) : .allAttachments
        return LinkPolicy(rule: rule, pastedImagesBecomeLinks: pastedImagesBecomeLinks)
    }

    /// Whether the email has only the folder's links (FR8, D17).
    var onlyFolderLinks: Bool {
        sharing == .folder && placement == .folderLinksOnly
    }
}

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case server, directory, onlyLargeFiles, sizeLimitMegabytes, pastedImagesBecomeLinks, expiry, warnIfSignOff
        case warningPhrases, sharing, placement, linkStyle, folderLinks
    }

    /// Reads stored settings. A setting that's missing, such as one added in a later version, or that can't be read
    /// gets its default, so the other settings are kept.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = Settings()
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? values.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        server = value(.server, defaults.server)
        directory = value(.directory, defaults.directory)
        onlyLargeFiles = value(.onlyLargeFiles, defaults.onlyLargeFiles)
        sizeLimitMegabytes = value(.sizeLimitMegabytes, defaults.sizeLimitMegabytes)
        pastedImagesBecomeLinks = value(.pastedImagesBecomeLinks, defaults.pastedImagesBecomeLinks)
        expiry = value(.expiry, defaults.expiry)
        warnIfSignOff = value(.warnIfSignOff, defaults.warnIfSignOff)
        warningPhrases = value(.warningPhrases, defaults.warningPhrases)
        sharing = value(.sharing, defaults.sharing)
        placement = value(.placement, defaults.placement)
        linkStyle = value(.linkStyle, defaults.linkStyle)
        folderLinks = value(.folderLinks, defaults.folderLinks)
    }
}

/// Reads and writes the settings, as JSON in the App Group's defaults.
struct SettingsStore {
    static let key = "settings"

    let defaults: UserDefaults

    init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    init?(groupIdentifier: String) {
        guard let defaults = UserDefaults(suiteName: groupIdentifier) else {
            return nil
        }
        self.defaults = defaults
    }

    /// The stored settings, or the defaults when there are none or they can't be read.
    func load() -> Settings {
        guard let data = defaults.data(forKey: Self.key),
            let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else {
            return Settings()
        }
        return settings
    }

    func save(_ settings: Settings) {
        guard let data = try? JSONEncoder().encode(settings) else {
            return
        }
        defaults.set(data, forKey: Self.key)
    }
}

/// The server address the user types, before logging in.
enum ServerAddress {
    enum Problem: Error, Equatable, LocalizedError {
        case empty
        case notHTTPS
        case invalid

        var errorDescription: String? {
            switch self {
            case .empty:
                return "Enter your Nextcloud server's address, such as https://cloud.example.com."
            case .notHTTPS:
                return "Use an https:// address. Files and passwords are never sent over plain http."
            case .invalid:
                return "That isn't a server address. Enter one such as https://cloud.example.com."
            }
        }
    }

    /// The server's URL. `https://` is added when no scheme is given, any other scheme is refused (NFR3), and a
    /// page's path, such as `/index.php/apps/files`, is cut off, keeping a path that Nextcloud is installed under.
    static func url(from text: String) throws -> URL {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw Problem.empty
        }
        if !text.contains("://") {
            text = "https://" + text
        }
        guard var parts = URLComponents(string: text), let scheme = parts.scheme else {
            throw Problem.invalid
        }
        guard scheme.lowercased() == "https" else {
            throw Problem.notHTTPS
        }
        guard let host = parts.host, !host.isEmpty, !host.contains(" ") else {
            throw Problem.invalid
        }
        var path = parts.path
        for page in ["/index.php", "/apps/", "/s/", "/login/"] {
            if let range = path.range(of: page) {
                path = String(path[..<range.lowerBound])
            }
        }
        while path.hasSuffix("/") {
            path.removeLast()
        }
        if path.hasSuffix("/login") {
            path.removeLast("/login".count)
        }
        parts.scheme = "https"
        parts.path = path
        parts.query = nil
        parts.fragment = nil
        parts.user = nil
        parts.password = nil
        guard let url = parts.url else {
            throw Problem.invalid
        }
        return url
    }
}
