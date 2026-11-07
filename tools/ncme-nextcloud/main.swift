import Foundation

@testable import NextcloudMailExtensionShared

// Runs the Nextcloud client's requests by hand, against the test server in .env (D14, docs/TESTING.md). Start it
// with scripts/nextcloud.sh, which loads .env. Each run uses a new app password and revokes it at the end.

let usage = """
    usage: scripts/nextcloud.sh <command>
      limits                                  the server's version and sharing limits
      mkdir <path>                            create a folder, and any folders missing on the way
      upload <file> <path>                    upload a file, never overwriting one
      share <path> [<YYYY-MM-DD>] [<password>]  create a link share, which doesn't expire without a date
      password <share-id> <password>          change a share's password
      unshare <share-id>                      delete a share
      rm <path>                               delete a file, or a folder with everything in it
      login                                   try the browser login, then revoke the app password it gave
    Paths are relative to the account's files, such as NextcloudMailExtensionDir001/test/a.txt.
    """

struct ToolError: LocalizedError {
    let errorDescription: String?

    init(_ text: String) {
        errorDescription = text
    }
}

func setting(_ name: String) throws -> String {
    guard let value = ProcessInfo.processInfo.environment[name], !value.isEmpty else {
        throw ToolError("\(name) isn't set. Run this through scripts/nextcloud.sh, which loads .env.")
    }
    return value
}

func perform(_ command: String, _ arguments: [String], _ client: NextcloudClient) async throws {
    switch (command, arguments.count) {
    case ("limits", 0):
        let limits = try await client.sharingLimits()
        print("Nextcloud \(limits.version), user ID \(client.userID)")
        print("passwords enforced: \(limits.passwordEnforced)")
        print(
            "default expiry: \(limits.defaultExpiryDays.map { "\($0) days" } ?? "none"), "
                + "enforced: \(limits.expiryEnforced)"
        )
    case ("mkdir", 1):
        try await client.createFolders(arguments[0])
    case ("upload", 2):
        try await client.upload(URL(fileURLWithPath: arguments[0]), to: arguments[1])
    case ("share", 1...3):
        let date = arguments.count > 1 ? arguments[1] : ""
        let share = try await client.share(
            arguments[0], expireDate: date, password: arguments.count > 2 ? arguments[2] : nil)
        print("id: \(share.id)\nview: \(share.url.absoluteString)\ndownload: \(share.downloadURL.absoluteString)")
        print("expires: \(share.expiration?.text ?? "never")")
    case ("password", 2):
        try await client.setPassword(arguments[1], forShare: arguments[0])
    case ("unshare", 1):
        try await client.deleteShare(arguments[0])
    case ("rm", 1):
        try await client.delete(arguments[0])
    default:
        throw ToolError(usage)
    }
}

func login(_ server: URL) async throws {
    let flow = try await NextcloudClient.startLogin(server: server)
    print("Open this page and log in within 10 minutes:\n\(flow.loginURL.absoluteString)")
    for _ in 0..<300 {
        if let account = try await NextcloudClient.pollLogin(flow) {
            let client = try await NextcloudClient.connect(account)
            print("Logged in as \(account.loginName), user ID \(client.userID), on \(account.server.absoluteString).")
            print("Got an app password of \(account.appPassword.count) characters.")
            try await client.revokeAppPassword()
            print("Revoked it again.")
            return
        }
        try await Task.sleep(nanoseconds: 2_000_000_000)
    }
    throw ToolError("Gave up waiting for the login.")
}

func run(_ arguments: [String]) async throws {
    guard let command = arguments.first else {
        print(usage)
        return
    }
    guard let server = URL(string: try setting("NCME_TEST_SERVER_URL")) else {
        throw ToolError("NCME_TEST_SERVER_URL isn't a URL.")
    }
    if command == "login" {
        try await login(server)
        return
    }
    let account = try await NextcloudClient.appPassword(
        server: server, loginName: try setting("NCME_TEST_USERNAME"), password: try setting("NCME_TEST_PASSWORD"))
    let client = try await NextcloudClient.connect(account)
    do {
        try await perform(command, Array(arguments.dropFirst()), client)
    } catch {
        try? await client.revokeAppPassword()
        throw error
    }
    try await client.revokeAppPassword()
}

do {
    try await run(Array(CommandLine.arguments.dropFirst()))
} catch {
    FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
    exit(1)
}
