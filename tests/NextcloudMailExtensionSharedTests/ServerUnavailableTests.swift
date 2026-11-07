import Foundation
import Testing

@testable import NextcloudMailExtensionShared

/// What the app, the popover and the send say when the server or the network is unavailable (T21,
/// docs/NEXTCLOUD.md, "Unavailable").
struct ServerUnavailableTests {
    static func online() async -> Bool { true }
    static func noNetwork() async -> Bool { false }

    /// `NextcloudClient.reaching` without its pause, on a Mac with or without a network.
    func reach<T>(network: Bool = true, _ request: () async throws -> T) async throws -> T {
        try await NextcloudClient.reaching(retryDelay: 0, hasNetwork: network ? Self.online : Self.noNetwork, request)
    }

    func response(_ status: Int, _ headers: [String: String] = [:]) throws -> HTTPURLResponse {
        let url = try #require(URL(string: "https://cloud.example.test/ocs/v2.php/cloud/user"))
        return try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers))
    }

    @Test func tellsMaintenanceModeFromOtherGatewayErrors() throws {
        let ocs = try response(503, ["X-Nextcloud-Maintenance-Mode": "1"])
        #expect(throws: NextcloudError.maintenance) { try NextcloudClient.status(of: ocs) }
        let dav = Data(
            """
            <?xml version="1.0" encoding="utf-8"?>
            <d:error xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">
              <s:exception>OCA\\DAV\\Exception\\ServerMaintenanceMode</s:exception>
            </d:error>
            """.utf8)
        #expect(throws: NextcloudError.maintenance) { try NextcloudClient.status(of: try response(503), data: dav) }
        for status in [502, 503, 504] {
            #expect(throws: NextcloudError.unavailable(status: status)) {
                try NextcloudClient.status(of: try response(status), data: Data("<html>Bad Gateway</html>".utf8))
            }
        }
        #expect(try NextcloudClient.status(of: try response(404)) == 404, "a 404 is the caller's to judge")
    }

    @Test func tellsAnotherSitesPageFromNextcloud() {
        let page = Data("<!DOCTYPE html><html><title>Error | 404</title></html>".utf8)
        #expect(throws: NextcloudError.notNextcloud(status: 404)) {
            try NextcloudClient.ocsData(UserData.self, from: page, status: 404)
        }
        #expect(throws: NextcloudError.notNextcloud(status: 405)) {
            try NextcloudClient.ocsData(UserData.self, from: page, status: 405)
        }
        let ocs404 = Data(
            #"{"ocs":{"meta":{"status":"failure","statuscode":404,"message":"Wrong share ID"},"data":[]}}"#.utf8)
        #expect(throws: NextcloudError.server(status: 404, reason: "Wrong share ID")) {
            try NextcloudClient.ocsData(UserData.self, from: ocs404, status: 404)
        }
    }

    @Test(arguments: [
        (URLError.Code.cannotFindHost, NextcloudError.cannotFindServer), (.dnsLookupFailed, .cannotFindServer),
        (.cannotConnectToHost, .cannotConnect), (.networkConnectionLost, .cannotConnect), (.timedOut, .timedOut),
    ])
    func saysWhyTheServerCantBeReached(code: URLError.Code, error: NextcloudError) async {
        await #expect(throws: error) {
            try await reach { throw URLError(code) }
        }
    }

    @Test func tellsNoNetworkFromLocalNetworkPrivacy() async {
        await #expect(throws: NextcloudError.noNetwork) {
            try await reach(network: false) {
                throw URLError(.notConnectedToInternet)
            }
        }
        await #expect(throws: NextcloudError.cannotFindServer, "the retry's own error counts") {
            var attempts = 0
            return try await reach { () throws -> Int in
                attempts += 1
                throw URLError(attempts == 1 ? .notConnectedToInternet : .cannotFindHost)
            }
        }
        await #expect(throws: URLError(.secureConnectionFailed), "other errors keep macOS's text") {
            try await reach {
                throw URLError(.secureConnectionFailed)
            }
        }
    }

    @Test func saysWhatHappenedInEachCase() {
        let texts: [(NextcloudError, String)] = [
            (.maintenance, "maintenance mode"), (.unavailable(status: 502), "isn't working at the moment (HTTP 502)"),
            (.notNextcloud(status: 404), "didn't answer as Nextcloud (HTTP 404)"), (.noNetwork, "isn't connected"),
            (.cannotFindServer, "couldn't find the Nextcloud server"), (.cannotConnect, "doesn't accept connections"),
            (.timedOut, "didn't answer in time"),
        ]
        for (error, text) in texts {
            #expect(error.localizedDescription.contains(text))
            #expect(error.serverUnavailable)
        }
        #expect(!NextcloudError.unauthorized.serverUnavailable && !NextcloudError.rateLimited.serverUnavailable)
    }

    @Test func tellsTheSendHowToGoAheadWhileTheServerIsUnavailable() {
        let text = Sender.alertText(for: NextcloudError.maintenance)
        #expect(text.hasPrefix(NextcloudError.maintenance.localizedDescription))
        #expect(text.hasSuffix(SendError.sendAttachedHint))
        #expect(Sender.alertText(for: NextcloudError.unauthorized) == NextcloudError.unauthorized.localizedDescription)
    }

    @Test func failsTheSendWithTheReasonAndTheHint() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let sender = Sender(
            Sender.Dependencies(
                settings: { SendFixtures.settings() },
                connect: { throw NextcloudError.unavailable(status: 502) },
                store: UploadLedgerStore(url: folder.appendingPathComponent("upload-ledger.json")),
                now: { SendFixtures.today }
            ))
        let result = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: UUID())
        guard case .failed(let text) = result else {
            Issue.record("Not failed: \(result)")
            return
        }
        #expect(text.contains("HTTP 502") && text.contains("turn off Sign"))
    }
}
