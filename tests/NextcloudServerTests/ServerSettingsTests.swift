import Foundation
import Testing

@testable import NextcloudMailExtensionShared

/// The test server's sharing settings, keys in Nextcloud's `core` app config that an admin can change through the
/// provisioning API (D18). They apply to the whole server, so tests that change them run on their own.
enum ServerSettings {
    static let enabled = TestServer.environment["NCME_TEST_CHANGE_SERVER_SETTINGS"] == "1"

    static let expiryMaximum = [
        "shareapi_default_expire_date": "yes",
        "shareapi_expire_after_n_days": "7",
        "shareapi_enforce_expire_date": "yes",
    ]
    static let passwordRequired = ["shareapi_enforce_links_password": "yes"]

    /// Runs `body` with the settings changed, then puts back what was there, deleting the keys that weren't set. It
    /// tries every key even if one fails.
    static func with(_ values: [String: String], _ body: () async throws -> Void) async throws {
        let admin = try adminAccount()
        let before = try await keys(admin)
        var original: [(key: String, value: String?)] = []
        for key in values.keys {
            original.append((key, before.contains(key) ? try await value(key, admin) : nil))
        }
        var failures: [Error] = []
        do {
            for (key, value) in values {
                try await set(key, value, admin)
            }
            try await body()
        } catch {
            failures.append(error)
        }
        for (key, value) in original {
            do {
                if let value {
                    try await set(key, value, admin)
                } else {
                    try await delete(key, admin)
                }
            } catch {
                failures.append(error)
            }
        }
        #expect(try await keys(admin) == before, "the server's settings weren't put back")
        if let failure = failures.first {
            throw failure
        }
    }

    /// The account with its own password. The admin requests ask for the password to be confirmed, which an app
    /// password can't do, so these requests alone use the account password (D18).
    static func adminAccount() throws -> NextcloudAccount {
        NextcloudAccount(
            server: try TestServer.server(), loginName: try #require(TestServer.environment["NCME_TEST_USERNAME"]),
            appPassword: try #require(TestServer.environment["NCME_TEST_PASSWORD"]))
    }

    static func keys(_ account: NextcloudAccount) async throws -> Set<String> {
        let data: ConfigData<[String]> = try await request("GET", nil, account)
        return Set(data.data)
    }

    static func value(_ key: String, _ account: NextcloudAccount) async throws -> String {
        let data: ConfigData<String> = try await request("GET", key, account)
        return data.data
    }

    static func set(_ key: String, _ value: String, _ account: NextcloudAccount) async throws {
        let _: Ignored = try await request("POST", key, account, form: [("value", value)])
    }

    static func delete(_ key: String, _ account: NextcloudAccount) async throws {
        let _: Ignored = try await request("DELETE", key, account)
    }

    private struct ConfigData<T: Decodable>: Decodable {
        var data: T
    }

    private static func request<T: Decodable>(
        _ method: String, _ key: String?, _ account: NextcloudAccount, form: [(String, String)] = []
    ) async throws -> T {
        let endpoint = "ocs/v2.php/apps/provisioning_api/api/v1/config/apps/core" + (key.map { "/" + $0 } ?? "")
        var request = URLRequest(url: NextcloudClient.url(account.server, endpoint))
        request.httpMethod = method
        let credentials = Data("\(account.loginName):\(account.appPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !form.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = NextcloudClient.formBody(form)
        }
        let (data, response) = try await NextcloudClient.defaultSession.data(for: request)
        return try NextcloudClient.ocsData(T.self, from: data, status: try NextcloudClient.status(of: response))
    }
}

/// An enforced expiry maximum and enforced passwords (T3b, docs/NEXTCLOUD.md). Run by
/// `scripts/test-nextcloud.sh --server-settings`, which runs nothing else, since these change the whole server.
@Suite(
    .enabled(if: TestServer.configured && ServerSettings.enabled, "run scripts/test-nextcloud.sh --server-settings"),
    .serialized)
struct ServerSettingsTests {
    @Test func shortensLinksToAnEnforcedMaximum() async throws {
        try await ServerSettings.with(ServerSettings.expiryMaximum) {
            try await TestServer.withFolder("enforced expiry") { client, folder in
                let limits = try await client.sharingLimits()
                #expect(limits.defaultExpiryDays == 7)
                #expect(limits.expiryEnforced)
                let path = NextcloudClient.join(folder, "a.txt")
                try await client.upload(Data("a".utf8), to: path)
                let today = Date()
                let maximum = LinkExpiry.days(7).expireDate(from: today, limits: limits)

                let never = try await client.share(path, expireDate: "", password: nil)
                #expect(never.expiration == ExpiryDate(server: maximum))

                let open = SharingLimits(version: limits.version, passwordEnforced: false, expiryEnforced: false)
                do {
                    let later = LinkExpiry.days(30).expireDate(from: today, limits: open)
                    _ = try await client.share(path, expireDate: later, password: nil)
                    Issue.record("The server accepted a date after its enforced maximum.")
                } catch NextcloudError.server(let status, let reason) {
                    #expect(status == 404)
                    #expect(reason == "Cannot set expiration date more than 7 days in the future")
                }

                let year = LinkExpiry.year.expireDate(from: today, limits: limits)
                #expect(year == maximum)
                let shortened = try await client.share(path, expireDate: year, password: nil)
                #expect(shortened.expiration == ExpiryDate(server: maximum))
                #expect(LinkExpiry.never.expireDate(from: today, limits: limits) == maximum)
            }
        }
    }

    @Test func refusesLinksWithoutAnEnforcedPassword() async throws {
        try await ServerSettings.with(ServerSettings.passwordRequired) {
            try await TestServer.withFolder("enforced password") { client, folder in
                let limits = try await client.sharingLimits()
                #expect(limits.passwordEnforced)
                let path = NextcloudClient.join(folder, "a.txt")
                try await client.upload(Data("a".utf8), to: path)
                do {
                    _ = try await client.share(path, expireDate: "", password: nil)
                    Issue.record("The server accepted a link without a password.")
                } catch NextcloudError.server(let status, let reason) {
                    #expect(status == 403)
                    #expect(reason == "Passwords are enforced for link and mail shares")
                }
                let share = try await client.share(path, expireDate: "", password: TestServer.newPassword())
                #expect(!share.id.isEmpty)
            }
        }
    }
}
