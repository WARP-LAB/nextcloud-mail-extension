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
    /// The server couldn't be reached although the Mac has a network: what macOS also reports when Local Network
    /// privacy blocks a server on the local network (docs/MAIL.md).
    case offline
    /// The Mac has no network at all (T21).
    case noNetwork
    /// The server's name doesn't resolve (T21).
    case cannotFindServer
    /// Nothing accepts connections at the server's address, as when its web server is stopped (T21).
    case cannotConnect
    /// The server didn't answer in time (T21).
    case timedOut
    /// Nextcloud is in maintenance mode: 503 with `X-Nextcloud-Maintenance-Mode: 1`, or WebDAV's
    /// `ServerMaintenanceMode` (T21, docs/NEXTCLOUD.md).
    case maintenance
    /// A gateway error, 502, 503 or 504, as when the web server runs but PHP doesn't (T21).
    case unavailable(status: Int)
    /// An answer that isn't Nextcloud's, such as a web server's own error page when the site is switched off (T21).
    case notNextcloud(status: Int)
    /// Any other refusal, with the server's reason.
    case server(status: Int, reason: String)
    case invalidResponse(String)

    /// Whether the server or the network is unavailable, rather than refusing this request (T21).
    var serverUnavailable: Bool {
        switch self {
        case .offline, .noNetwork, .cannotFindServer, .cannotConnect, .timedOut, .maintenance, .unavailable,
            .notNextcloud:
            return true
        default:
            return false
        }
    }

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
                + "NextcloudMailExtension and NextcloudMailExtensionPlugIn in System Settings > Privacy & Security > "
                + "Local Network. If NextcloudMailExtensionPlugIn isn't listed, open the toolbar button in a message "
                + "window, and allow it when macOS asks."
        case .noNetwork:
            return "This Mac isn't connected to a network, so files can't become links."
        case .cannotFindServer:
            return "This Mac couldn't find the Nextcloud server. Check the network, or the server's address in "
                + "NextcloudMailExtension."
        case .cannotConnect:
            return "The Nextcloud server doesn't accept connections at the moment, so it may be down. Try again later."
        case .timedOut:
            return "The Nextcloud server didn't answer in time. It may be down, or the network may be slow."
        case .maintenance:
            return "Nextcloud is in maintenance mode, so files can't become links until it's back. Try again later."
        case .unavailable(let status):
            return "The Nextcloud server isn't working at the moment (HTTP \(status)), so files can't become links. "
                + "Try again later, or tell the server's admin."
        case .notNextcloud(let status):
            return "The server didn't answer as Nextcloud (HTTP \(status)). It may be down, or its address may have "
                + "changed: check it in NextcloudMailExtension."
        case .server(let status, let reason):
            return reason.isEmpty ? "Nextcloud refused the request (HTTP \(status))." : "Nextcloud: \(reason)"
        case .invalidResponse(let what):
            return "Nextcloud's answer to \(what) couldn't be read."
        }
    }
}
