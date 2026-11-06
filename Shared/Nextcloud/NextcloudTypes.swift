import Foundation

/// A Nextcloud account: the server, and the app password from Nextcloud's browser login (NFR3).
struct NextcloudAccount: Equatable, Codable {
    var server: URL
    var loginName: String
    var appPassword: String
}

/// The server's rules for link shares (docs/NEXTCLOUD.md, "Capabilities").
struct SharingLimits: Equatable {
    var version: String
    var passwordEnforced: Bool
    /// The number of days after which link shares expire by default, or nil when they don't expire by default.
    var defaultExpiryDays: Int?
    /// Whether the default number of days is also the maximum.
    var expiryEnforced: Bool
}

/// A public link share.
struct Share: Equatable, Codable {
    var id: String
    /// The view link, `/s/<token>`.
    var url: URL
    /// The date the server set, or nil for a link that doesn't expire. Show this, never the requested date (FR4).
    var expiration: ExpiryDate?

    var downloadURL: URL {
        url.appendingPathComponent("download")
    }
}

/// Nextcloud's browser login, Login Flow v2: the page the user opens, and where to ask for the result.
struct LoginFlow: Equatable {
    var loginURL: URL
    var pollEndpoint: URL
    var token: String
}

enum NextcloudError: Error, Equatable, LocalizedError {
    /// The folder or file already exists. Uploads never overwrite (NFR3).
    case exists(String)
    /// A folder on the way to the path doesn't exist.
    case missingParent(String)
    case notFound(String)
    /// The server didn't accept the app password, which may have been revoked.
    case unauthorized
    /// Too many requests: Nextcloud allows each user 20 new shares in 10 minutes by default (docs/NEXTCLOUD.md).
    case rateLimited
    /// The server couldn't be reached. macOS also reports this when Local Network privacy blocks a server on the
    /// local network (docs/MAIL.md).
    case offline
    /// Any other refusal, with the server's reason.
    case server(status: Int, reason: String)
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .exists(let path):
            return "“\(path)” already exists on Nextcloud."
        case .missingParent(let path):
            return "The folder for “\(path)” doesn't exist on Nextcloud."
        case .notFound(let what):
            return "\(what) wasn't found on Nextcloud."
        case .unauthorized:
            return "Nextcloud didn't accept the app password. Log in again in NextcloudMailExtension."
        case .rateLimited:
            return "Nextcloud allows only a limited number of new links in a few minutes. Try again in 10 minutes."
        case .offline:
            return "This Mac couldn't reach Nextcloud. If the server is on your local network, turn on "
                + "NextcloudMailExtension in System Settings > Privacy & Security > Local Network."
        case .server(let status, let reason):
            return reason.isEmpty ? "Nextcloud refused the request (HTTP \(status))." : "Nextcloud: \(reason)"
        case .invalidResponse(let what):
            return "Nextcloud's answer to \(what) couldn't be read."
        }
    }
}
