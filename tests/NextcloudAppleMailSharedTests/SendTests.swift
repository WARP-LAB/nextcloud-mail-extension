import Foundation
import Testing

@testable import NextcloudAppleMailShared

struct EncodedWordsTests {
    @Test(arguments: [
        ("Plain subject", "Plain subject"),
        ("=?utf-8?Q?P=C4=81rskats_par_t=C4=81ri=C5=86iem?=", "Pārskats par tāriņiem"),
        ("=?UTF-8?B?UMSBcnNrYXRz?=", "Pārskats"),
        ("Re: =?utf-8?Q?a?= =?utf-8?Q?b?= c", "Re: ab c"),
        ("=?iso-8859-1?q?caf=E9?=", "café"),
        ("=?utf-8*lv?Q?=C4=81?=", "ā"),
        ("=?x-unknown?Q?abc?=", "=?x-unknown?Q?abc?="),
    ])
    func decodesSubjects(header: String, expected: String) {
        #expect(EncodedWords.decode(header) == expected)
    }
}

struct UploadLedgerTests {
    func withStore(_ body: (UploadLedgerStore) throws -> Void) throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        try body(UploadLedgerStore(url: folder.appendingPathComponent("ledger/upload-ledger.json")))
    }

    @Test func storesAndPrunesEntries() throws {
        try withStore { store in
            let now = SendFixtures.today
            #expect(store.load() == UploadLedger())
            try store.update("old", now: now.addingTimeInterval(-UploadLedger.lifetime - 1)) { $0.folder = "Mail/a" }
            try store.update("new", now: now) { entry in
                entry.folder = "Mail/b"
                entry.files["key"] = UploadLedger.StoredFile(path: "Mail/b/a b.pdf")
            }
            let ledger = store.load()
            #expect(ledger.entries.keys.sorted() == ["new"])
            #expect(ledger.entries["new"]?.files["key"]?.name == "a b.pdf")
            try store.remove("new")
            #expect(store.load().entries.isEmpty)
        }
    }

    @Test func keysFilesByTheirContents() {
        #expect(UploadLedger.key(for: Data("a".utf8)) == UploadLedger.key(for: Data("a".utf8)))
        #expect(UploadLedger.key(for: Data("a".utf8)).count == 64)
        #expect(UploadLedger.key(for: Data("a".utf8)) != UploadLedger.key(for: Data("b".utf8)))
    }
}

struct SendFlowTests {
    func run(
        _ name: String, settings: Settings = SendFixtures.settings(), password: String? = nil,
        nextcloud: FakeNextcloud = FakeNextcloud(), record: MessageRecord? = nil
    ) async throws -> (output: MimeMessage, record: MessageRecord) {
        let message = try Fixture.message(name)
        let record = record ?? MessageRecord(UploadLedger.Entry(updated: SendFixtures.today))
        var flow = SendFlow(settings: settings, service: nextcloud)
        flow.today = SendFixtures.today
        let files = settings.linkPolicy.linkedFiles(in: message, signatureContentIDs: [])
        let data = try await flow.run(message, files: files, password: password, record: record)
        return (MimeMessage(data), record)
    }

    @Test func sharesTheEmailsFolderOnceByDefault() async throws {
        let nextcloud = FakeNextcloud()
        let (output, record) = try await run("t29-second", nextcloud: nextcloud)
        #expect(record.entry.folder == "Mail/2026-11-06 [probe ff] t29")
        #expect(nextcloud.files.keys.sorted() == record.entry.files.values.map(\.path).sorted())
        #expect(nextcloud.files.count == 2)
        let call = FakeNextcloud.ShareCall(path: "Mail/2026-11-06 [probe ff] t29", expireDate: "2026-11-13")
        #expect(nextcloud.shares == [call])
        let text = try #require(output.root.text)
        #expect(text.contains("View: https://cloud.example.test/s/share1\n"))
        #expect(text.contains("Download: https://cloud.example.test/s/share1/download?files=dummy-1MB.pdf\n"))
        #expect(text.contains("link expires 13 Nov 2026"))
        #expect(!text.contains("View all files in email"))
        #expect(output.files.isEmpty)
    }

    @Test func sharesEachFileWhenSetTo() async throws {
        let nextcloud = FakeNextcloud()
        let settings = SendFixtures.settings { $0.sharing = .eachFile }
        let (output, _) = try await run("t29-second", settings: settings, nextcloud: nextcloud)
        #expect(nextcloud.shares.count == 2)
        #expect(nextcloud.shares.allSatisfy { $0.path.hasPrefix("Mail/2026-11-06 [probe ff] t29/") })
        let text = try #require(output.root.text)
        #expect(text.contains("Download: https://cloud.example.test/s/share1/download\n"))
        #expect(text.contains("View: https://cloud.example.test/s/share2\n"))
    }

    @Test func addsTheFolderShareForAllFilesLinksWhenEachFileIsShared() async throws {
        let nextcloud = FakeNextcloud()
        let settings = SendFixtures.settings {
            $0.sharing = .eachFile
            $0.folderLinks = true
        }
        let (output, _) = try await run("t29-second", settings: settings, nextcloud: nextcloud)
        #expect(nextcloud.shares.count == 3)
        #expect(nextcloud.shares.last?.path == "Mail/2026-11-06 [probe ff] t29")
        #expect(output.root.text?.contains("View all files in email: https://cloud.example.test/s/share3") == true)
    }

    @Test func givesOnlyTheFolderLinksWhenSetTo() async throws {
        let nextcloud = FakeNextcloud()
        let settings = SendFixtures.settings { $0.placement = .folderLinksOnly }
        let (output, _) = try await run("t29-second", settings: settings, nextcloud: nextcloud)
        #expect(nextcloud.shares.count == 1)
        let text = try #require(output.root.text)
        #expect(text.contains("dummy-1MB.pdf (1 KB, link expires 13 Nov 2026)\n"))
        #expect(text.contains("View all files in email: https://cloud.example.test/s/share1\n"))
        #expect(text.contains("Download all files in email: https://cloud.example.test/s/share1/download\n"))
        #expect(!text.contains("?files="))
    }

    @Test func reusesWhatTheRecordHas() async throws {
        let nextcloud = FakeNextcloud()
        let (first, record) = try await run("t29-first", nextcloud: nextcloud)
        let (second, _) = try await run("t29-second", nextcloud: nextcloud, record: record)
        #expect(nextcloud.uploads == 2)
        #expect(nextcloud.shares.count == 1)
        #expect(first.text("html").joined().contains("share1/download?files="))
        #expect(second.root.text?.contains("share1/download?files=") == true)
    }

    @Test func retriesOnlyTheFilesThatFailed() async throws {
        let nextcloud = FakeNextcloud()
        let message = try Fixture.message("t29-second")
        let failing = try #require(message.files.last?.filename)
        nextcloud.failing = [failing]
        let record = MessageRecord(UploadLedger.Entry(updated: SendFixtures.today))
        do {
            _ = try await run("t29-second", nextcloud: nextcloud, record: record)
            Issue.record("The send didn't stop.")
        } catch let error as SendError {
            #expect(error.localizedDescription.contains("“\(failing)”"))
            #expect(error.localizedDescription.contains("Insufficient Storage"))
        }
        #expect(record.entry.files.count == 1)
        #expect(nextcloud.shares.isEmpty)
        nextcloud.failing = []
        _ = try await run("t29-second", nextcloud: nextcloud, record: record)
        #expect(nextcloud.uploads == 2)
        #expect(nextcloud.folders.filter { $0.hasPrefix("Mail/2026") }.count == 1)
    }

    @Test func uploadsAFileAttachedTwiceOnce() async throws {
        let nextcloud = FakeNextcloud()
        let (output, _) = try await run("t15-second", nextcloud: nextcloud)
        #expect(nextcloud.uploads == 1)
        #expect(output.root.text?.components(separatedBy: "files=dummy-1MB.bin").count == 3)
    }

    @Test func numbersANameThatsTaken() async throws {
        let nextcloud = FakeNextcloud()
        let message = try Fixture.message("t29-second")
        let name = try #require(message.files.first?.filename)
        let record = MessageRecord(UploadLedger.Entry(updated: SendFixtures.today))
        record.entry.folder = "Mail/2026-11-06 [probe ff] t29"
        try await nextcloud.createFolders("Mail/2026-11-06 [probe ff] t29")
        nextcloud.files["Mail/2026-11-06 [probe ff] t29/\(name)"] = Data("older".utf8)
        let (output, _) = try await run("t29-second", nextcloud: nextcloud, record: record)
        let numbered = NextcloudNames.numbered(name, 2)
        #expect(nextcloud.files["Mail/2026-11-06 [probe ff] t29/\(numbered)"] != nil)
        #expect(output.root.text?.contains(NextcloudClient.encode(numbered)) == true)
    }

    @Test func stopsWithoutAPasswordTheServerRequires() async throws {
        let nextcloud = FakeNextcloud()
        nextcloud.limits.passwordEnforced = true
        await #expect(throws: SendError.passwordRequired) {
            _ = try await run("t29-second", nextcloud: nextcloud)
        }
        #expect(nextcloud.uploads == 0)
        let (output, _) = try await run("t29-second", password: "a long password", nextcloud: nextcloud)
        #expect(nextcloud.shares.first?.password == "a long password")
        #expect(output.root.text?.contains(LinkText.passwordNotice) == true)
        #expect(output.root.text?.contains("a long password") == false)
    }

    @Test func shortensTheExpiryToTheServersMaximum() async throws {
        let nextcloud = FakeNextcloud()
        nextcloud.limits.defaultExpiryDays = 3
        nextcloud.limits.expiryEnforced = true
        _ = try await run("t29-second", settings: SendFixtures.settings { $0.expiry = .never }, nextcloud: nextcloud)
        #expect(nextcloud.shares.first?.expireDate == "2026-11-09")
    }

    @Test func replacesWhatBreaksAFolderShareDownload() {
        #expect(NextcloudNames.folderShareName("Pārskats #1 100% ok?.pdf") == "Pārskats _1 100_ ok_.pdf")
        #expect(NextcloudNames.folderShareName("a&b+c;d [1].pdf") == "a&b+c;d [1].pdf")
    }

    @Test func encodesNamesInTheDownloadLink() throws {
        let url = try #require(URL(string: "https://cloud.example.test/s/abc"))
        let share = Share(id: "1", url: url)
        #expect(
            SendFlow.downloadURL(of: "Pārskats #1 a+b&c.pdf", in: share).absoluteString
                == "https://cloud.example.test/s/abc/download?files=P%C4%81rskats%20%231%20a%2Bb%26c.pdf")
    }
}
