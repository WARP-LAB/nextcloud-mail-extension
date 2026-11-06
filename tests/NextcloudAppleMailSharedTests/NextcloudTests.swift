import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The Nextcloud client's parsing and URLs, without a server. The server tests are in tests/NextcloudServerTests.
struct NextcloudClientTests {
    func client(server: String = "https://cloud.example.test/nextcloud/", userID: String = "user name") throws
        -> NextcloudClient
    {
        let account = NextcloudAccount(server: try #require(URL(string: server)), loginName: "user", appPassword: "x")
        return NextcloudClient(account: account, userID: userID)
    }

    @Test func encodesWebDAVPaths() throws {
        let url = try client().davURL("Dir/2026-11-06 Report ā/#1 %.txt")
        let files = "https://cloud.example.test/nextcloud/remote.php/dav/files/user%20name"
        #expect(url.absoluteString == files + "/Dir/2026-11-06%20Report%20%C4%81/%231%20%25.txt")
    }

    @Test func keepsTheServersOwnPath() throws {
        let server = try #require(URL(string: "https://cloud.example.test"))
        #expect(
            NextcloudClient.url(server, "ocs/v2.php/cloud/user").absoluteString
                == "https://cloud.example.test/ocs/v2.php/cloud/user")
        #expect(
            try client(server: "https://cloud.example.test/").davURL("/a/").absoluteString
                == "https://cloud.example.test/remote.php/dav/files/user%20name/a")
    }

    @Test func encodesForms() throws {
        let body = NextcloudClient.formBody([("path", "/Dir/a b.txt"), ("password", "p&ss=+ā")])
        #expect(String(bytes: body, encoding: .utf8) == "path=%2FDir%2Fa%20b.txt&password=p%26ss%3D%2B%C4%81")
    }

    @Test func joinsPaths() {
        #expect(NextcloudClient.join("Dir/", "a") == "Dir/a")
        #expect(NextcloudClient.join("", "a") == "a")
        #expect(NextcloudClient.join("/Dir/Sub", "a b") == "Dir/Sub/a b")
    }

    @Test func readsAShare() throws {
        let json = """
            {"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"id":"7","token":"abc",\
            "url":"https://cloud.example.test/s/abc","expiration":"2026-11-13 23:59:59","item_type":"file"}}}
            """
        let share = try NextcloudClient.ocsData(ShareData.self, from: Data(json.utf8), status: 200).share()
        #expect(share.id == "7")
        #expect(share.url.absoluteString == "https://cloud.example.test/s/abc")
        #expect(share.downloadURL.absoluteString == "https://cloud.example.test/s/abc/download")
        #expect(share.expiration == ExpiryDate(server: "2026-11-13"))
    }

    @Test func readsAShareWithANumericIDAndNoExpiry() throws {
        let json = #"{"ocs":{"meta":{"statuscode":200},"data":{"id":12,"url":"https://c.test/s/x","expiration":null}}}"#
        let share = try NextcloudClient.ocsData(ShareData.self, from: Data(json.utf8), status: 200).share()
        #expect(share.id == "12")
        #expect(share.expiration == nil)
    }

    @Test(arguments: [
        (400, "Password needs to be at least 10 characters long."),
        (404, "Expiration date is in the past"),
    ])
    func reportsTheServersReason(status: Int, reason: String) {
        let json = #"{"ocs":{"meta":{"status":"failure","statuscode":\#(status),"message":"\#(reason)"},"data":[]}}"#
        #expect(throws: NextcloudError.server(status: status, reason: reason)) {
            try NextcloudClient.ocsData(ShareData.self, from: Data(json.utf8), status: status)
        }
    }

    @Test func reportsResponsesThatArentOCS() {
        #expect(throws: NextcloudError.server(status: 502, reason: "bad gateway")) {
            try NextcloudClient.ocsData(ShareData.self, from: Data("<html>".utf8), status: 502)
        }
    }

    @Test(arguments: [(401, NextcloudError.unauthorized), (429, .rateLimited)])
    func treatsSomeStatusesAlike(status: Int, error: NextcloudError) throws {
        let url = try #require(URL(string: "https://cloud.example.test/ocs/v2.php/cloud/user"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil))
        #expect(throws: error) {
            try NextcloudClient.status(of: response)
        }
    }

    @Test func saysWhereToAllowAServerThatCantBeReached() async {
        await #expect(throws: NextcloudError.offline) {
            try await NextcloudClient.reaching { throw URLError(.notConnectedToInternet) }
        }
        await #expect(throws: URLError(.timedOut)) {
            try await NextcloudClient.reaching { throw URLError(.timedOut) }
        }
        #expect(NextcloudError.offline.localizedDescription.contains("Local Network"))
    }

    @Test func readsWebDAVErrors() {
        let xml = """
            <?xml version="1.0" encoding="utf-8"?>
            <d:error xmlns:d="DAV:" xmlns:s="http://sabredav.org/ns">
              <s:exception>Sabre\\DAV\\Exception\\MethodNotAllowed</s:exception>
              <s:message>The resource you tried to create already exists</s:message>
            </d:error>
            """
        #expect(NextcloudClient.davMessage(Data(xml.utf8)) == "The resource you tried to create already exists")
        #expect(NextcloudClient.davMessage(Data()) == "")
    }

    @Test func readsTheSharingLimits() throws {
        let open = """
            {"ocs":{"meta":{"statuscode":200},"data":{"version":{"major":35,"string":"35.0.2"},"capabilities":\
            {"files_sharing":{"public":{"enabled":true,"password":{"enforced":false},\
            "expire_date":{"enabled":false}}}}}}}
            """
        let limits = try NextcloudClient.ocsData(CapabilitiesData.self, from: Data(open.utf8), status: 200).limits
        #expect(
            limits
                == SharingLimits(
                    version: "35.0.2", passwordEnforced: false, defaultExpiryDays: nil, expiryEnforced: false))
    }

    @Test(arguments: [#""30""#, "30"])
    func readsEnforcedLimits(days: String) throws {
        let strict = """
            {"ocs":{"meta":{"statuscode":200},"data":{"version":{"string":"34.0.1"},"capabilities":{"files_sharing":\
            {"public":{"password":{"enforced":true},"expire_date":{"enabled":true,"days":\(days),"enforced":true}}}}}}}
            """
        let limits = try NextcloudClient.ocsData(CapabilitiesData.self, from: Data(strict.utf8), status: 200).limits
        #expect(
            limits
                == SharingLimits(version: "34.0.1", passwordEnforced: true, defaultExpiryDays: 30, expiryEnforced: true)
        )
    }
}

struct LinkExpiryTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        return calendar
    }()

    static let today = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31, hour: 12)) ?? Date()

    static func limits(maximum: Int? = nil) -> SharingLimits {
        SharingLimits(
            version: "35.0.2", passwordEnforced: false, defaultExpiryDays: maximum, expiryEnforced: maximum != nil)
    }

    @Test(arguments: [
        (LinkExpiry.week, "2026-02-07"), (.month, "2026-02-28"), (.year, "2027-01-31"), (.days(10), "2026-02-10"),
        (.months(3), "2026-04-30"), (.years(2), "2028-01-31"), (.never, ""),
    ])
    func addsThePeriodByCalendar(expiry: LinkExpiry, date: String) {
        #expect(expiry.expireDate(today: Self.today, calendar: Self.calendar, limits: Self.limits()) == date)
    }

    @Test(arguments: [(LinkExpiry.year, "2026-03-02"), (.never, "2026-03-02"), (.week, "2026-02-07")])
    func shortensToAnEnforcedMaximum(expiry: LinkExpiry, date: String) {
        #expect(expiry.expireDate(today: Self.today, calendar: Self.calendar, limits: Self.limits(maximum: 30)) == date)
    }

    @Test func ignoresADefaultThatIsntEnforced() {
        let limits = SharingLimits(version: "35", passwordEnforced: false, defaultExpiryDays: 7, expiryEnforced: false)
        #expect(LinkExpiry.never.expireDate(today: Self.today, calendar: Self.calendar, limits: limits) == "")
    }
}

struct NextcloudNamesTests {
    static let day = LinkExpiryTests.calendar.date(from: DateComponents(year: 2026, month: 11, day: 5)) ?? Date()

    @Test(arguments: [
        ("Quarterly report", "2026-11-05 Quarterly report"),
        (nil, "2026-11-05 Email"),
        (" ... ", "2026-11-05 Email"),
        ("Re: a/b\\c", "2026-11-05 Re: a-b-c"),
        ("Line\nbreak\tand tab", "2026-11-05 Line break and tab"),
        ("..Hidden. ", "2026-11-05 Hidden"),
        (String(repeating: "x", count: 80), "2026-11-05 " + String(repeating: "x", count: 60)),
        (String(repeating: "y", count: 59) + " .z", "2026-11-05 " + String(repeating: "y", count: 59)),
    ])
    func namesTheEmailsFolder(subject: String?, name: String) {
        #expect(NextcloudNames.folder(date: Self.day, subject: subject, calendar: LinkExpiryTests.calendar) == name)
    }

    @Test func numbersFileNamesUsedTwice() {
        let names = ["a.pdf", "a.pdf", "A.PDF", "b", "b", ".env", "", "x/y.txt", "..", " c.txt "]
        #expect(
            NextcloudNames.uniqueFiles(names) == [
                "a.pdf", "a (2).pdf", "A (3).PDF", "b", "b (2)", ".env", "attachment", "x-y.txt", "attachment (2)",
                "c.txt",
            ])
    }
}
