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

    /// What FR3's size limit is compared with.
    enum SizeLimitScope: String, Codable, CaseIterable {
        /// Each file larger than the limit becomes links. The default.
        case eachFile
        /// When the files together are larger than the limit, all of them become links.
        case allFiles
    }

    static let defaultDirectory = "MailAttachments"
    /// The largest size limit, a terabyte, so that any number typed or stored turns into bytes.
    static let maximumSizeLimitMegabytes = 1_000_000.0

    /// The server address the user typed to log in. Requests use the server that the login returned.
    var server = ""
    /// The directory on Nextcloud where each email gets its own folder (FR2).
    var directory = Settings.defaultDirectory
    /// FR3: true when only files over `sizeLimitMegabytes` become links, false when all files do.
    var onlyLargeFiles = false
    var sizeLimitMegabytes = 10.0
    var sizeLimitScope = SizeLimitScope.eachFile
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
        let megabytes = sizeLimitMegabytes.isNaN ? 0 : min(max(0, sizeLimitMegabytes), Self.maximumSizeLimitMegabytes)
        let bytes = Int((megabytes * 1_000_000).rounded())
        let rule: LinkPolicy.Rule
        switch (onlyLargeFiles, sizeLimitScope) {
        case (false, _):
            rule = .allAttachments
        case (true, .eachFile):
            rule = .largerThan(bytes: bytes)
        case (true, .allFiles):
            rule = .togetherLargerThan(bytes: bytes)
        }
        return LinkPolicy(rule: rule, pastedImagesBecomeLinks: pastedImagesBecomeLinks)
    }

    /// FR3's rule for one email, after the choice in its toolbar popover.
    func linkPolicy(for choice: LinkChoice) -> LinkPolicy {
        switch choice {
        case .useSettings:
            return linkPolicy
        case .allFiles:
            return LinkPolicy(rule: .allAttachments, pastedImagesBecomeLinks: true)
        case .keepAttached:
            return LinkPolicy(rule: .noFiles)
        }
    }

    /// Whether the email has only the folder's links (FR8, D17).
    var onlyFolderLinks: Bool {
        sharing == .folder && placement == .folderLinksOnly
    }
}

extension Settings: Codable {
    private enum CodingKeys: String, CodingKey {
        case server, directory, onlyLargeFiles, sizeLimitMegabytes, sizeLimitScope, pastedImagesBecomeLinks, expiry
        case warnIfSignOff, warningPhrases, sharing, placement, linkStyle, folderLinks
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
        sizeLimitScope = value(.sizeLimitScope, defaults.sizeLimitScope)
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

/// Which of an email's files become links, as chosen in its toolbar popover (FR3).
enum LinkChoice: String, CaseIterable {
    /// The settings decide. The default.
    case useSettings
    /// Every file becomes links, pasted images too, whatever the size limit. Images in the signature stay.
    case allFiles
    /// Every file stays attached.
    case keepAttached

    /// The popover's stored choice, where anything else, such as none, means the settings decide.
    init(stored: String?) {
        self = stored.flatMap(Self.init(rawValue:)) ?? .useSettings
    }
}

/// Decimal numbers that the user types, such as the size limit in MB. "." and "," both separate the decimals,
/// whatever the region, so that "0.2" isn't read as 0 where the region writes "0,2".
enum DecimalText {
    /// The number, or nil for text that isn't a number that's zero or more, such as "", "1.2.3" or "-1".
    static func value(of text: String) -> Double? {
        let text = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
        guard text.contains(where: \.isNumber), text.filter({ $0 == "." }).count <= 1,
            text.allSatisfy({ ("0"..."9").contains($0) || $0 == "." })
        else {
            return nil
        }
        return Double(text.hasSuffix(".") ? text + "0" : text)
    }

    /// The number with up to three decimals, without trailing zeros or grouping, such as "0.2" or "10".
    static func text(of value: Double, separator: String = Locale.current.decimalSeparator ?? ".") -> String {
        var text = String(format: "%.3f", value)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") {
            text.removeLast()
        }
        return text.replacingOccurrences(of: ".", with: separator)
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
