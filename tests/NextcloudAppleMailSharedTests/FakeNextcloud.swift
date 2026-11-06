import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// Nextcloud in memory, recording what the send flow asks of it.
final class FakeNextcloud: NextcloudService {
    struct ShareCall: Equatable {
        var path: String
        var expireDate: String
        var password: String?
    }

    var limits = SharingLimits(version: "35.0.2", passwordEnforced: false, expiryEnforced: false)
    var folders = Set<String>()
    var files: [String: Data] = [:]
    var shares: [ShareCall] = []
    var deleted: [String] = []
    var uploads = 0
    /// Uploads of files with these names fail, as a full disk would.
    var failing = Set<String>()

    func sharingLimits() async throws -> SharingLimits {
        limits
    }

    func createFolders(_ path: String) async throws {
        var current: [String] = []
        for name in NextcloudClient.names(in: path) {
            current.append(name)
            folders.insert(current.joined(separator: "/"))
        }
    }

    func createUniqueFolder(named name: String, in directory: String) async throws -> String {
        for number in 1...100 {
            let path = NextcloudClient.join(directory, number == 1 ? name : "\(name) (\(number))")
            if !folders.contains(path) {
                folders.insert(path)
                return path
            }
        }
        throw NextcloudError.exists(name)
    }

    func upload(_ file: URL, to path: String) async throws {
        let names = NextcloudClient.names(in: path)
        guard folders.contains(names.dropLast().joined(separator: "/")) else {
            throw NextcloudError.missingParent(path)
        }
        guard files[path] == nil else {
            throw NextcloudError.exists(path)
        }
        if let name = names.last, failing.contains(name) {
            throw NextcloudError.server(status: 507, reason: "Insufficient Storage")
        }
        files[path] = try Data(contentsOf: file)
        uploads += 1
    }

    func share(_ path: String, expireDate: String, password: String?) async throws -> Share {
        shares.append(ShareCall(path: path, expireDate: expireDate, password: password))
        let url = try #require(URL(string: "https://cloud.example.test/s/share\(shares.count)"))
        return Share(id: "\(shares.count)", url: url, expiration: ExpiryDate(server: expireDate))
    }

    func delete(_ path: String) async throws {
        deleted.append(path)
        folders = folders.filter { $0 != path && !$0.hasPrefix(path + "/") }
        files = files.filter { !$0.key.hasPrefix(path + "/") }
    }
}

enum SendFixtures {
    static var today: Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 12)) ?? Date()
    }

    static func settings(_ change: (inout Settings) -> Void = { _ in }) -> Settings {
        var settings = Settings()
        settings.directory = "Mail"
        settings.expiry = .week
        change(&settings)
        return settings
    }

    /// The fixture with another message ID, for a second message.
    static func message(_ name: String, id: String) throws -> Data {
        let text = try #require(String(bytes: try Fixture.data(name), encoding: .utf8))
        return Data(text.replacingOccurrences(of: "00000000-0000-4000-8000-000000000001", with: id).utf8)
    }
}
