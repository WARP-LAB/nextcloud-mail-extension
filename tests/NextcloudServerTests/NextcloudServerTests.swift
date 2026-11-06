import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The test server in .env (D14). These tests run only from scripts/test-nextcloud.sh, which loads it. Each test
/// works on its own app password and in its own folder inside `NCAM_TEST_DIRECTORY`, and deletes both.
enum TestServer {
    static let environment = ProcessInfo.processInfo.environment
    static let configured = environment["NCAM_TEST_SERVER_URL"] != nil

    static var directory: String {
        environment["NCAM_TEST_DIRECTORY"] ?? "NextcloudAppleMailTests"
    }

    static func server() throws -> URL {
        try #require(environment["NCAM_TEST_SERVER_URL"].flatMap { URL(string: $0) })
    }

    static func account() async throws -> NextcloudAccount {
        let login = try #require(environment["NCAM_TEST_USERNAME"])
        let password = try #require(environment["NCAM_TEST_PASSWORD"])
        return try await NextcloudClient.appPassword(server: try server(), loginName: login, password: password)
    }

    /// Runs `body` with a client and a new folder, then deletes the folder and revokes the app password.
    static func withFolder(_ name: String, _ body: (NextcloudClient, String) async throws -> Void) async throws {
        let client = try await NextcloudClient.connect(try await account())
        var folder: String?
        var failure: Error?
        do {
            try await client.createFolders(directory)
            let stamp = Date().formatted(
                .iso8601.year().month().day().dateSeparator(.omitted).time(includingFractionalSeconds: false)
                    .timeSeparator(.omitted))
            let path = try await client.createUniqueFolder(named: "\(stamp) \(name)", in: directory)
            folder = path
            try await body(client, path)
        } catch {
            failure = error
        }
        if let folder {
            try? await client.delete(folder)
        }
        try? await client.revokeAppPassword()
        if let failure {
            throw failure
        }
    }

    /// Fetches a link as a recipient would, following redirects, with a share password for public WebDAV.
    static func get(_ url: URL, password: String? = nil) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        if let password {
            let credentials = Data("anonymous:\(password)".utf8).base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession(configuration: .ephemeral).data(for: request)
        return (data, try #require(response as? HTTPURLResponse))
    }

    /// Opens a link as a browser would, with cookies: when the share's password page appears, posts the password
    /// with the page's request token, and returns where that leads.
    static func openWithPassword(_ url: URL, password: String) async throws -> (Data, HTTPURLResponse) {
        let session = URLSession(configuration: .ephemeral)
        let (page, pageResponse) = try await session.data(from: url)
        let response = try #require(pageResponse as? HTTPURLResponse)
        let html = String(bytes: page, encoding: .utf8) ?? ""
        guard let form = response.url, form.path.contains("/authenticate/"),
            let token = html.firstMatch(of: #/data-requesttoken="([^"]+)"/#)?.1
        else {
            return (page, response)
        }
        var post = URLRequest(url: form)
        post.httpMethod = "POST"
        post.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        post.httpBody = NextcloudClient.formBody([("requesttoken", String(token)), ("password", password)])
        let (data, postResponse) = try await session.data(for: post)
        return (data, try #require(postResponse as? HTTPURLResponse))
    }

    static func newPassword() -> String {
        "ncam-" + UUID().uuidString.prefix(13)
    }
}

@Suite(.enabled(if: TestServer.configured, "needs the test server: run scripts/test-nextcloud.sh"))
struct NextcloudServerTests {
    @Test func readsTheUserAndLimitsAndRevokesTheAppPassword() async throws {
        let account = try await TestServer.account()
        let client = try await NextcloudClient.connect(account)
        #expect(!client.userID.isEmpty)
        let limits = try await client.sharingLimits()
        #expect((Int(limits.version.prefix { $0 != "." }) ?? 0) >= 34)
        try await client.revokeAppPassword()
        await #expect(throws: NextcloudError.unauthorized) {
            try await NextcloudClient.connect(account)
        }
    }

    @Test func startsTheBrowserLogin() async throws {
        let server = try TestServer.server()
        let flow = try await NextcloudClient.startLogin(server: server)
        #expect(flow.loginURL.host == server.host)
        #expect(flow.pollEndpoint.host == server.host)
        let account = try await NextcloudClient.pollLogin(flow)
        #expect(account == nil)
    }

    @Test func createsFoldersAndNeverOverwrites() async throws {
        try await TestServer.withFolder("folders") { client, folder in
            let report = NextcloudClient.join(folder, "Report")
            try await client.createFolder(report)
            await #expect(throws: NextcloudError.exists(report)) {
                try await client.createFolder(report)
            }
            #expect(try await client.exists(report))
            let second = try await client.createUniqueFolder(named: "Report", in: folder)
            #expect(second == NextcloudClient.join(folder, "Report (2)"))
            let orphan = NextcloudClient.join(folder, "missing/child")
            await #expect(throws: NextcloudError.missingParent(orphan)) {
                try await client.createFolder(orphan)
            }
            #expect(try await !client.exists(orphan))
            let file = NextcloudClient.join(report, "a.txt")
            try await client.upload(Data("first".utf8), to: file)
            #expect(try await client.exists(file))
            await #expect(throws: NextcloudError.exists(file)) {
                try await client.upload(Data("second".utf8), to: file)
            }
            await #expect(throws: NextcloudError.missingParent(NextcloudClient.join(orphan, "a.txt"))) {
                try await client.upload(Data("lost".utf8), to: NextcloudClient.join(orphan, "a.txt"))
            }
            try await client.delete(file)
            await #expect(throws: NextcloudError.notFound("“\(file)”")) {
                try await client.delete(file)
            }
        }
    }

    @Test func checksTheConnection() async throws {
        try await TestServer.withFolder("check") { client, folder in
            var settings = Settings()
            settings.directory = folder
            let report = await ConnectionCheck.run(settings: settings, account: client.account)
            #expect(report.passed, "\(report.lines)")
            #expect(report.text.contains("“\(folder)” exists"))
            settings.directory = NextcloudClient.join(folder, "missing")
            let missing = await ConnectionCheck.run(settings: settings, account: client.account)
            #expect(missing.passed, "\(missing.lines)")
            #expect(missing.text.contains("doesn't exist yet"))
        }
    }

    @Test func sharesAFileWithLinksThatWork() async throws {
        try await TestServer.withFolder("share") { client, folder in
            let contents = Data("Pārskats\n".utf8)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent("ncam-\(UUID().uuidString).txt")
            try contents.write(to: file)
            defer {
                try? FileManager.default.removeItem(at: file)
            }
            let path = NextcloudClient.join(folder, "Pārskats #1 %.txt")
            try await client.upload(file, to: path)
            let date = LinkExpiry.week.expireDate(today: Date(), limits: try await client.sharingLimits())
            let share = try await client.share(path, expireDate: date, password: nil)
            #expect(share.expiration == ExpiryDate(server: date))

            let (_, page) = try await TestServer.get(share.url)
            #expect(page.statusCode == 200)
            #expect(page.mimeType == "text/html")
            let (download, _) = try await TestServer.get(share.downloadURL)
            #expect(download == contents)

            try await client.deleteShare(share.id)
            let (_, gone) = try await TestServer.get(share.url)
            #expect(gone.statusCode == 404)
            await #expect(throws: NextcloudError.notFound("The share")) {
                try await client.deleteShare(share.id)
            }
        }
    }

    @Test func followsTheExpiryRules() async throws {
        try await TestServer.withFolder("expiry") { client, folder in
            let path = NextcloudClient.join(folder, "a.txt")
            try await client.upload(Data("a".utf8), to: path)
            let limits = try await client.sharingLimits()
            let never = try await client.share(path, expireDate: "", password: nil)
            let far = try await client.share(path, expireDate: "2099-01-01", password: nil)
            if !limits.expiryEnforced {
                #expect(never.expiration == nil)
                #expect(far.expiration == ExpiryDate(server: "2099-01-01"))
            }
            do {
                _ = try await client.share(path, expireDate: "2020-01-01", password: nil)
                Issue.record("The server accepted an expiry date in the past.")
            } catch NextcloudError.server(let status, let reason) {
                #expect(status == 404)
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test func protectsSharesWithAPassword() async throws {
        try await TestServer.withFolder("password") { client, folder in
            let contents = Data("secret\n".utf8)
            let path = NextcloudClient.join(folder, "a.txt")
            try await client.upload(contents, to: path)
            let password = TestServer.newPassword()
            let share = try await client.share(path, expireDate: "", password: password)

            let (page, response) = try await TestServer.get(share.downloadURL)
            #expect(page != contents)
            #expect(response.url?.path.contains("/authenticate/") == true)
            let dav = NextcloudClient.url(
                try TestServer.server(), "public.php/dav/files/" + share.url.lastPathComponent)
            let (file, _) = try await TestServer.get(dav, password: password)
            #expect(file == contents)

            let changed = TestServer.newPassword()
            try await client.setPassword(changed, forShare: share.id)
            let (_, old) = try await TestServer.get(dav, password: password)
            #expect(old.statusCode == 401)
            let (again, _) = try await TestServer.get(dav, password: changed)
            #expect(again == contents)

            do {
                _ = try await client.share(path, expireDate: "", password: "short")
                Issue.record("The server accepted the password “short”.")
            } catch NextcloudError.server(let status, let reason) {
                #expect(status == 400)
                #expect(!reason.isEmpty)
            }
        }
    }

    @Test func downloadsOneFileOfAFolderShareAfterItsPassword() async throws {
        try await TestServer.withFolder("folder password") { client, folder in
            let first = Data("first\n".utf8)
            try await client.upload(first, to: NextcloudClient.join(folder, "Pārskats #1.txt"))
            try await client.upload(Data("second\n".utf8), to: NextcloudClient.join(folder, "b.txt"))
            let password = TestServer.newPassword()
            let share = try await client.share(folder, expireDate: "", password: password)
            var single = try #require(URLComponents(url: share.downloadURL, resolvingAgainstBaseURL: false))
            single.queryItems = [URLQueryItem(name: "files", value: "Pārskats #1.txt")]
            let url = try #require(single.url)

            let (page, locked) = try await TestServer.get(url)
            #expect(page != first)
            #expect(locked.url?.path.contains("/authenticate/") == true)
            let (file, response) = try await TestServer.openWithPassword(url, password: password)
            let got = "\(response.statusCode) \(response.mimeType ?? "") from \(response.url?.path ?? "")"
            #expect(file == first, "got \(got)")
        }
    }

    @Test func zipsAFolderShare() async throws {
        try await TestServer.withFolder("zip ā") { client, folder in
            let first = Data("first\n".utf8)
            try await client.upload(first, to: NextcloudClient.join(folder, "a.txt"))
            try await client.upload(Data("second\n".utf8), to: NextcloudClient.join(folder, "Pārskats ļoti.txt"))
            let share = try await client.share(folder, expireDate: "", password: nil)

            let (zip, response) = try await TestServer.get(share.downloadURL)
            #expect(response.mimeType == "application/zip")
            #expect(zip.prefix(2) == Data("PK".utf8))
            #expect(zip.range(of: Data("Pārskats ļoti.txt".utf8)) != nil)
            var single = try #require(URLComponents(url: share.downloadURL, resolvingAgainstBaseURL: false))
            single.queryItems = [URLQueryItem(name: "files", value: "a.txt")]
            let (one, _) = try await TestServer.get(try #require(single.url))
            #expect(one == first)

            try await client.delete(folder)
            let (_, gone) = try await TestServer.get(share.url)
            #expect(gone.statusCode == 404)
        }
    }
}
