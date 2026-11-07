import Foundation
import Testing

@testable import NextcloudMailExtensionShared

/// The settings' defaults and storage, and the server address check (T2).
struct SettingsTests {
    func decode(_ json: String) throws -> Settings {
        try JSONDecoder().decode(Settings.self, from: Data(json.utf8))
    }

    @Test func hasThePRDsDefaults() {
        let settings = Settings()
        #expect(settings.directory == "MailAttachments")
        #expect(settings.linkPolicy.rule == .allAttachments)
        #expect(settings.sizeLimitScope == .eachFile)
        #expect(settings.expiry == .month)
        #expect(settings.pastedImagesBecomeLinks)
        #expect(settings.warnIfSignOff)
        #expect(settings.warningPhrases.isEmpty)
        #expect(settings.sharing == .folder)
        #expect(settings.placement == .whereEachFileWas)
        #expect(settings.linkStyle == .viewAndDownload)
        #expect(!settings.folderLinks)
        #expect(!settings.linksBelowText)
    }

    @Test func roundTrips() throws {
        var settings = Settings()
        settings.server = "https://cloud.example.test"
        settings.directory = "Mail/Out"
        settings.onlyLargeFiles = true
        settings.sizeLimitMegabytes = 2.5
        settings.sizeLimitScope = .allFiles
        settings.pastedImagesBecomeLinks = false
        settings.expiry = .years(2)
        settings.warnIfSignOff = false
        settings.warningPhrases = ["attach", "pielikum"]
        settings.sharing = .eachFile
        settings.placement = .belowText
        settings.linkStyle = .downloadOnly
        settings.folderLinks = true
        #expect(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)) == settings)
    }

    @Test func givesMissingSettingsTheirDefaults() throws {
        #expect(try decode("{}") == Settings())
        let settings = try decode(#"{"directory":"Old","folderLinks":true}"#)
        var expected = Settings()
        expected.directory = "Old"
        expected.folderLinks = true
        #expect(settings == expected)
    }

    @Test func keepsTheOtherSettingsWhenOneCantBeRead() throws {
        let settings = try decode(#"{"sharing":"somethingNew","expiry":{"weeks":{"_0":2}},"warnIfSignOff":false}"#)
        #expect(settings.sharing == .folder)
        #expect(settings.expiry == .month)
        #expect(!settings.warnIfSignOff)
    }

    @Test func storesInDefaults() throws {
        let suite = "lv.warp.nextcloudmailextension.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
        }
        let store = SettingsStore(defaults: defaults)
        #expect(store.load() == Settings())
        var settings = Settings()
        settings.expiry = .days(10)
        store.save(settings)
        #expect(SettingsStore(defaults: defaults).load() == settings)
        defaults.set(Data("not JSON".utf8), forKey: SettingsStore.key)
        #expect(store.load() == Settings())
    }

    @Test(arguments: [
        ("  Mail attachments/ ", "Mail attachments"),
        ("/Mail//Out/", "Mail/Out"),
        ("a/../b/./c", "a/b/c"),
        ("", "MailAttachments"),
        (" / ", "MailAttachments"),
    ])
    func cleansTheDirectory(directory: String, expected: String) {
        var settings = Settings()
        settings.directory = directory
        #expect(settings.uploadDirectory == expected)
    }

    @Test func turnsTheSizeLimitIntoBytes() {
        var settings = Settings()
        settings.onlyLargeFiles = true
        settings.sizeLimitMegabytes = 2.5
        #expect(settings.linkPolicy.rule == .largerThan(bytes: 2_500_000))
        settings.sizeLimitMegabytes = 10.2
        #expect(settings.linkPolicy.rule == .largerThan(bytes: 10_200_000), "rounded, not cut off")
        settings.sizeLimitMegabytes = 0.2
        settings.sizeLimitScope = .allFiles
        #expect(settings.linkPolicy.rule == .togetherLargerThan(bytes: 200_000))
        settings.sizeLimitMegabytes = -1
        #expect(settings.linkPolicy.rule == .togetherLargerThan(bytes: 0))
        settings.sizeLimitMegabytes = 1e300
        #expect(settings.linkPolicy.rule == .togetherLargerThan(bytes: 1_000_000_000_000), "a terabyte at most")
        settings.sizeLimitMegabytes = .nan
        #expect(settings.linkPolicy.rule == .togetherLargerThan(bytes: 0))
    }

    @Test(
        arguments: [
            ("0.2", 0.2), ("0,2", 0.2), ("10.2", 10.2), (" 10,25 ", 10.25), ("5", 5), ("5.", 5), (".5", 0.5),
            ("", nil), ("1.2.3", nil), ("1,2.3", nil), ("-1", nil), ("1e3", nil), ("abc", nil), (".", nil),
        ] as [(String, Double?)])
    func readsDecimalsWithEitherSeparator(text: String, value: Double?) {
        #expect(DecimalText.value(of: text) == value)
    }

    @Test func showsDecimalsWithTheUsersSeparator() {
        #expect(DecimalText.text(of: 0.2, separator: ".") == "0.2")
        #expect(DecimalText.text(of: 0.2, separator: ",") == "0,2")
        #expect(DecimalText.text(of: 10, separator: ".") == "10")
        #expect(DecimalText.text(of: 0.1 + 0.2, separator: ".") == "0.3")
        #expect(DecimalText.text(of: 2.0005, separator: ".") == "2.001")
        #expect(DecimalText.text(of: 1_000_000, separator: ",") == "1000000")
    }

    @Test func addsTheLinksForAllFilesForTwoOrMoreWithTheSwitchOrBelowTheText() {
        for sharing in Settings.Sharing.allCases {
            var settings = Settings()
            settings.sharing = sharing
            #expect(!settings.addsAllFilesLinks(fileCount: 2), "inline, the switch off")
            settings.folderLinks = true
            #expect(settings.addsAllFilesLinks(fileCount: 2))
            #expect(!settings.addsAllFilesLinks(fileCount: 1), "one file's own links are enough")
            settings.folderLinks = false
            settings.placement = .belowText
            #expect(settings.linksBelowText)
            #expect(settings.addsAllFilesLinks(fileCount: 2), "below the text, whatever the switch")
            #expect(!settings.addsAllFilesLinks(fileCount: 1))
        }
    }

    @Test func keepsTheStoredBelowTheTextPlacement() throws {
        // Stored as "folderLinksOnly" when the setting meant only the folder's links (D28).
        #expect(try decode(#"{"placement":"folderLinksOnly"}"#).placement == .belowText)
        let stored = String(bytes: try JSONEncoder().encode(Settings.Placement.belowText), encoding: .utf8)
        #expect(stored == #""folderLinksOnly""#)
    }
}

struct ServerAddressTests {
    @Test(arguments: [
        ("cloud.example.test", "https://cloud.example.test"),
        ("  https://cloud.example.test/  ", "https://cloud.example.test"),
        ("HTTPS://cloud.example.test", "https://cloud.example.test"),
        ("https://cloud.example.test:8443/nextcloud/", "https://cloud.example.test:8443/nextcloud"),
        ("https://cloud.example.test/index.php/apps/files/?dir=/", "https://cloud.example.test"),
        ("https://cloud.example.test/nextcloud/apps/files/", "https://cloud.example.test/nextcloud"),
        ("https://cloud.example.test/login", "https://cloud.example.test"),
        ("https://cloud.example.test/s/abc123", "https://cloud.example.test"),
        ("https://user:secret@cloud.example.test/#top", "https://cloud.example.test"),
        ("https://cloud.example.test/logins", "https://cloud.example.test/logins"),
    ])
    func acceptsHTTPSAddresses(text: String, expected: String) throws {
        #expect(try ServerAddress.url(from: text).absoluteString == expected)
    }

    @Test func refusesOtherAddresses() {
        #expect(throws: ServerAddress.Problem.empty) { try ServerAddress.url(from: "  ") }
        #expect(throws: ServerAddress.Problem.notHTTPS) { try ServerAddress.url(from: "http://cloud.example.test") }
        #expect(throws: ServerAddress.Problem.notHTTPS) { try ServerAddress.url(from: "ftp://cloud.example.test") }
        #expect(throws: ServerAddress.Problem.invalid) { try ServerAddress.url(from: "https://") }
        #expect(throws: ServerAddress.Problem.invalid) { try ServerAddress.url(from: "cloud example") }
    }
}

struct MailCheckTests {
    func withContainer(_ body: (MailCheck) throws -> Void) throws {
        let container = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: container, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: container)
        }
        try body(MailCheck(container: container))
    }

    @Test func answersARequestOnce() throws {
        try withContainer { check in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            #expect(check.pendingRequest(now: now) == nil)
            let request = try check.request(now: now)
            #expect(check.pendingRequest(now: now.addingTimeInterval(5)) == request)
            #expect(check.answer(to: request) == nil)
            let report = ConnectionCheck.Report(passed: true, lines: ["Nextcloud 35.0.2."])
            try check.answer(request, with: report, now: now.addingTimeInterval(6))
            #expect(check.answer(to: request)?.report == report)
            #expect(check.pendingRequest(now: now.addingTimeInterval(7)) == nil)
        }
    }

    @Test func ignoresOldRequests() throws {
        try withContainer { check in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            _ = try check.request(now: now)
            #expect(check.pendingRequest(now: now.addingTimeInterval(MailCheck.lifetime + 1)) == nil)
        }
    }

    @Test func replacesTheEarlierRequestAndAnswer() throws {
        try withContainer { check in
            let now = Date(timeIntervalSince1970: 1_800_000_000)
            let first = try check.request(now: now)
            try check.answer(first, with: .failed("Not logged in."), now: now)
            let second = try check.request(now: now)
            #expect(check.answer(to: first) == nil)
            #expect(check.answer(to: second) == nil)
            #expect(check.pendingRequest(now: now) == second)
        }
    }

    @Test func notesTheServersRules() {
        let open = SharingLimits(
            version: "35.0.2", passwordEnforced: false, defaultExpiryDays: 7, expiryEnforced: false)
        #expect(ConnectionCheck.notes(on: open).isEmpty)
        let strict = SharingLimits(
            version: "35.0.2", passwordEnforced: true, defaultExpiryDays: 30, expiryEnforced: true)
        #expect(ConnectionCheck.notes(on: strict).count == 2)
        #expect(ConnectionCheck.notes(on: strict)[1].contains("30 days"))
    }

    @Test func reportsAMissingAccount() async {
        let report = await ConnectionCheck.run(settings: Settings(), account: nil)
        #expect(!report.passed)
        #expect(report.text.contains("Not logged in"))
    }
}
