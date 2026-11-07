import Foundation

/// The requests in docs/NEXTCLOUD.md. Paths are relative to the user's files, with `/` between names, such as
/// `NextcloudMailExtension/2026-11-05 Report/report.pdf`.
struct NextcloudClient {
    let account: NextcloudAccount
    /// The user ID, which WebDAV paths need. It can differ from the login name.
    let userID: String
    var session: URLSession = NextcloudClient.defaultSession

    static let userAgent = "NextcloudMailExtension"

    /// A session without cookies. Nextcloud ties its session cookie to the app password that logged in, so a cookie
    /// kept from a revoked app password makes later requests fail with 401 (docs/NEXTCLOUD.md).
    static let defaultSession: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }()

    /// Connects to the account's server, and finds the user ID.
    static func connect(_ account: NextcloudAccount, session: URLSession = NextcloudClient.defaultSession) async throws
        -> NextcloudClient
    {
        let client = NextcloudClient(account: account, userID: account.loginName, session: session)
        let user: UserData = try await client.ocs("GET", "cloud/user")
        return NextcloudClient(account: account, userID: user.id, session: session)
    }

    // MARK: - Logging in

    /// Starts the browser login. The user opens `loginURL`, and `pollLogin` then gets the app password.
    static func startLogin(server: URL, session: URLSession = NextcloudClient.defaultSession) async throws -> LoginFlow
    {
        var request = URLRequest(url: url(server, "index.php/login/v2"))
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, status) = try await send(request, session)
        guard status == 200, let flow = try? JSONDecoder().decode(LoginFlowData.self, from: data),
            let login = URL(string: flow.login), let endpoint = URL(string: flow.poll.endpoint)
        else {
            throw NextcloudError.server(status: status, reason: "The browser login couldn't be started.")
        }
        return LoginFlow(loginURL: login, pollEndpoint: endpoint, token: flow.poll.token)
    }

    /// The account once the user has logged in, or nil while they haven't yet.
    static func pollLogin(_ flow: LoginFlow, session: URLSession = NextcloudClient.defaultSession) async throws
        -> NextcloudAccount?
    {
        var request = URLRequest(url: flow.pollEndpoint)
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([("token", flow.token)])
        let (data, status) = try await send(request, session)
        if status == 404 {
            return nil
        }
        guard status == 200, let result = try? JSONDecoder().decode(LoginResultData.self, from: data),
            let server = URL(string: result.server)
        else {
            throw NextcloudError.invalidResponse("the browser login")
        }
        return NextcloudAccount(server: server, loginName: result.loginName, appPassword: result.appPassword)
    }

    /// Turns an account password into an app password. Only the tests and the command-line tool use this. The app
    /// logs in through the browser, so it never sees the account password (NFR3).
    static func appPassword(
        server: URL, loginName: String, password: String, session: URLSession = NextcloudClient.defaultSession
    ) async throws -> NextcloudAccount {
        let login = NextcloudAccount(server: server, loginName: loginName, appPassword: password)
        let client = NextcloudClient(account: login, userID: loginName, session: session)
        let data: AppPasswordData = try await client.ocs("GET", "core/getapppassword")
        return NextcloudAccount(server: server, loginName: loginName, appPassword: data.apppassword)
    }

    /// Revokes the app password the client uses, as logging out does.
    func revokeAppPassword() async throws {
        let _: Ignored = try await ocs("DELETE", "core/apppassword")
    }

    // MARK: - Server limits

    func sharingLimits() async throws -> SharingLimits {
        let data: CapabilitiesData = try await ocs("GET", "cloud/capabilities")
        return data.limits
    }

    // MARK: - Password policy (T16)

    /// The server's reason for refusing `password` as a link password, or nil when its password policy accepts it.
    /// Throws when the server can't check it, such as without the password policy app (docs/NEXTCLOUD.md).
    func passwordProblem(_ password: String) async throws -> String? {
        let data: PasswordCheckData = try await ocs(
            "POST", "apps/password_policy/api/v1/validate", form: [("password", password)])
        return data.passed ? nil : (data.reason ?? "Nextcloud's password policy doesn't accept this password.")
    }

    /// A password that the server's password policy accepts. Throws when the server can't make one.
    func generatedPassword() async throws -> String {
        let data: GeneratedPasswordData = try await ocs("GET", "apps/password_policy/api/v1/generate")
        return data.password
    }

    // MARK: - Folders and files

    func createFolder(_ path: String) async throws {
        let (data, status) = try await Self.send(davRequest("MKCOL", path), session)
        switch status {
        case 201:
            return
        case 405:
            throw NextcloudError.exists(path)
        case 409:
            throw NextcloudError.missingParent(path)
        default:
            throw NextcloudError.server(status: status, reason: Self.davMessage(data))
        }
    }

    /// Creates each folder in a path that doesn't exist yet, such as the settings' directory.
    func createFolders(_ path: String) async throws {
        var current: [String] = []
        for name in Self.names(in: path) {
            current.append(name)
            do {
                try await createFolder(current.joined(separator: "/"))
            } catch NextcloudError.exists {
                continue
            }
        }
    }

    /// Creates the folder `name` in `directory`, or `name (2)` and so on if it exists, and returns its path.
    func createUniqueFolder(named name: String, in directory: String) async throws -> String {
        for number in 1...100 {
            let path = Self.join(directory, number == 1 ? name : "\(name) (\(number))")
            do {
                try await createFolder(path)
                return path
            } catch NextcloudError.exists {
                continue
            }
        }
        throw NextcloudError.exists(Self.join(directory, name))
    }

    /// Uploads a file, refusing to overwrite one that's there (NFR3).
    func upload(_ file: URL, to path: String) async throws {
        var request = davRequest("PUT", path)
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        let (data, response) = try await Self.reaching { try await session.upload(for: request, fromFile: file) }
        try Self.checkUpload(data, response, path)
    }

    func upload(_ contents: Data, to path: String) async throws {
        var request = davRequest("PUT", path)
        request.setValue("*", forHTTPHeaderField: "If-None-Match")
        let (data, response) = try await Self.reaching { try await session.upload(for: request, from: contents) }
        try Self.checkUpload(data, response, path)
    }

    /// Deletes a file or a folder with everything in it.
    func delete(_ path: String) async throws {
        let (data, status) = try await Self.send(davRequest("DELETE", path), session)
        switch status {
        case 200, 204:
            return
        case 404:
            throw NextcloudError.notFound("“\(path)”")
        default:
            throw NextcloudError.server(status: status, reason: Self.davMessage(data))
        }
    }

    /// Whether a file or folder exists, from a `PROPFIND` of the item alone.
    func exists(_ path: String) async throws -> Bool {
        var request = davRequest("PROPFIND", path)
        request.setValue("0", forHTTPHeaderField: "Depth")
        let (data, status) = try await Self.send(request, session)
        switch status {
        case 207:
            return true
        case 404:
            return false
        default:
            throw NextcloudError.server(status: status, reason: Self.davMessage(data))
        }
    }

    // MARK: - Shares

    /// Creates a public link share. `expireDate` is `YYYY-MM-DD`, or empty for a link that doesn't expire (FR4).
    func share(_ path: String, expireDate: String, password: String?) async throws -> Share {
        var form = [("path", "/" + Self.names(in: path).joined(separator: "/")), ("shareType", "3")]
        form.append(("expireDate", expireDate))
        if let password, !password.isEmpty {
            form.append(("password", password))
        }
        let data: ShareData = try await ocs("POST", "apps/files_sharing/api/v1/shares", form: form)
        return try data.share()
    }

    /// Changes a share's expiry date, `YYYY-MM-DD` or empty for none, and returns the share with the date the server
    /// set (FR4).
    func setExpireDate(_ date: String, forShare id: String) async throws -> Share {
        let data: ShareData = try await ocs(
            "PUT", "apps/files_sharing/api/v1/shares/\(Self.encode(id))", form: [("expireDate", date)])
        return try data.share()
    }

    func setPassword(_ password: String, forShare id: String) async throws {
        let _: Ignored = try await ocs(
            "PUT", "apps/files_sharing/api/v1/shares/\(Self.encode(id))", form: [("password", password)])
    }

    func deleteShare(_ id: String) async throws {
        do {
            let _: Ignored = try await ocs("DELETE", "apps/files_sharing/api/v1/shares/\(Self.encode(id))")
        } catch NextcloudError.server(404, _) {
            throw NextcloudError.notFound("The share")
        }
    }

    // MARK: - Requests

    private func ocs<T: Decodable>(_ method: String, _ endpoint: String, form: [(String, String)] = []) async throws
        -> T
    {
        var request = authorized(URLRequest(url: Self.url(account.server, "ocs/v2.php/" + endpoint)))
        request.httpMethod = method
        request.setValue("true", forHTTPHeaderField: "OCS-APIRequest")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if !form.isEmpty {
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.httpBody = Self.formBody(form)
        }
        let (data, status) = try await Self.send(request, session)
        return try Self.ocsData(T.self, from: data, status: status)
    }

    private func davRequest(_ method: String, _ path: String) -> URLRequest {
        var request = authorized(URLRequest(url: davURL(path)))
        request.httpMethod = method
        return request
    }

    private func authorized(_ request: URLRequest) -> URLRequest {
        var request = request
        let credentials = Data("\(account.loginName):\(account.appPassword)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    func davURL(_ path: String) -> URL {
        let names = [userID] + Self.names(in: path)
        return Self.url(account.server, "remote.php/dav/files/" + names.map(Self.encode).joined(separator: "/"))
    }

    private static func send(_ request: URLRequest, _ session: URLSession) async throws -> (Data, Int) {
        let (data, response) = try await reaching { try await session.data(for: request) }
        return (data, try status(of: response))
    }

    /// Runs a request, turning "offline", which is also what a server blocked by Local Network privacy gives, into
    /// `NextcloudError.offline`, which says where to allow it. "Offline" is retried once after `retryDelay`: macOS
    /// refuses the first request a new build makes to the local network even when it's allowed, then lets the next
    /// one through (docs/MAIL.md, "Network").
    static func reaching<T>(retryDelay: UInt64 = 1_000_000_000, _ request: () async throws -> T) async throws -> T {
        do {
            return try await request()
        } catch let error as URLError where error.code == .notConnectedToInternet {
            try await Task.sleep(nanoseconds: retryDelay)
            do {
                return try await request()
            } catch let error as URLError where error.code == .notConnectedToInternet {
                throw NextcloudError.offline
            }
        }
    }

    /// The response's status, after throwing for the ones every request treats the same.
    static func status(of response: URLResponse) throws -> Int {
        guard let http = response as? HTTPURLResponse else {
            throw NextcloudError.invalidResponse("a request")
        }
        switch http.statusCode {
        case 401:
            throw NextcloudError.unauthorized
        case 429:
            throw NextcloudError.rateLimited
        default:
            return http.statusCode
        }
    }

    private static func checkUpload(_ data: Data, _ response: URLResponse, _ path: String) throws {
        let status = try status(of: response)
        switch status {
        case 200, 201, 204:
            return
        case 412:
            throw NextcloudError.exists(path)
        case 404, 409:
            throw NextcloudError.missingParent(path)
        default:
            throw NextcloudError.server(status: status, reason: davMessage(data))
        }
    }
}

extension NextcloudClient {
    // MARK: - Encoding and parsing

    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Percent-encodes everything but letters, digits and `-._~`, for a name in a URL path or a form value.
    static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// The server's URL with an endpoint added, keeping any path the server is installed under.
    static func url(_ server: URL, _ endpoint: String) -> URL {
        var base = server.absoluteString
        while base.hasSuffix("/") {
            base.removeLast()
        }
        return URL(string: base + "/" + endpoint) ?? server
    }

    static func formBody(_ fields: [(String, String)]) -> Data {
        Data(fields.map { "\(encode($0.0))=\(encode($0.1))" }.joined(separator: "&").utf8)
    }

    static func names(in path: String) -> [String] {
        path.split(separator: "/").map(String.init)
    }

    static func join(_ directory: String, _ name: String) -> String {
        (names(in: directory) + [name]).joined(separator: "/")
    }

    /// The `data` of an OCS response, or the server's reason for refusing.
    static func ocsData<T: Decodable>(_ type: T.Type, from data: Data, status: Int) throws -> T {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let meta = try? decoder.decode(OCSEnvelope<Ignored>.self, from: data).ocs.meta else {
            throw NextcloudError.server(status: status, reason: HTTPURLResponse.localizedString(forStatusCode: status))
        }
        guard (200...299).contains(status), meta.statuscode == 100 || meta.statuscode == 200 else {
            let code = (200...299).contains(status) ? meta.statuscode : status
            throw NextcloudError.server(status: code, reason: meta.message ?? "")
        }
        do {
            return try decoder.decode(OCSEnvelope<T>.self, from: data).ocs.data
        } catch {
            throw NextcloudError.invalidResponse(String(describing: T.self))
        }
    }

    /// The reason in a WebDAV error, such as "The resource you tried to create already exists".
    static func davMessage(_ data: Data) -> String {
        let body = String(bytes: data, encoding: .utf8) ?? ""
        guard let match = body.firstMatch(of: #/<s:message>([^<]*)</s:message>/#) else {
            return ""
        }
        return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
