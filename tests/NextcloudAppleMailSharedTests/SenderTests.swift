import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// Mail's `encode()` calls, from auto-saves to Mail Drop (docs/MAIL.md).
struct SenderTests {
    final class World {
        let nextcloud = FakeNextcloud()
        var settings = SendFixtures.settings()
        var loggedIn = true
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var now = SendFixtures.today

        lazy var sender = Sender(
            Sender.Dependencies(
                settings: { [unowned self] in settings },
                connect: { [unowned self] in loggedIn ? nextcloud : nil },
                store: UploadLedgerStore(url: folder.appendingPathComponent("upload-ledger.json")),
                now: { [unowned self] in now }
            ))

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }

        func encode(_ name: String, autoSave: Bool = false) async throws -> SendResult {
            await sender.encode(try Fixture.data(name), isAutoSave: autoSave, contextID: UUID())
        }

        func encode(_ data: Data) async -> SendResult {
            await sender.encode(data, isAutoSave: false, contextID: UUID())
        }
    }

    @Test func leavesAutoSavesAndMessagesWithoutFilesAlone() async throws {
        let world = World()
        #expect(try await world.encode("t29-first", autoSave: true) == .unchanged)
        #expect(try await world.encode("t34-second") == .unchanged)
        #expect(world.nextcloud.uploads == 0)
    }

    @Test func uploadsOnceForBothSendCalls() async throws {
        let world = World()
        guard case .rewritten = try await world.encode("t29-first") else {
            Issue.record("The first call wasn't rewritten.")
            return
        }
        guard case .rewritten(let data) = try await world.encode("t29-second") else {
            Issue.record("The second call wasn't rewritten.")
            return
        }
        #expect(world.nextcloud.uploads == 2)
        #expect(world.nextcloud.shares.count == 1)
        #expect(MimeMessage(data).files.isEmpty)
    }

    @Test func stopsWhenNotLoggedIn() async throws {
        let world = World()
        world.loggedIn = false
        #expect(try await world.encode("t29-second") == .failed(SendError.notSetUp.localizedDescription))
        let reply = try SendFixtures.message("t34-second", id: "00000000-0000-4000-8000-000000000002")
        #expect(await world.encode(reply) == .unchanged)
    }

    @Test func repeatsAFailureForTheNextCallOnly() async throws {
        let world = World()
        let message = try Fixture.message("t29-second")
        world.nextcloud.failing = Set(message.files.map(\.filename))
        guard case .failed(let text) = try await world.encode("t29-first") else {
            Issue.record("The first call didn't fail.")
            return
        }
        world.nextcloud.failing = []
        #expect(try await world.encode("t29-second") == .failed(text))
        #expect(world.nextcloud.uploads == 0)
        guard case .rewritten = try await world.encode("t29-second") else {
            Issue.record("Sending again didn't retry.")
            return
        }
        #expect(world.nextcloud.uploads == 2)
    }

    @Test func forgetsAFailureAfterAMinute() async throws {
        let world = World()
        world.nextcloud.failing = Set(try Fixture.message("t29-second").files.map(\.filename))
        _ = try await world.encode("t29-first")
        world.nextcloud.failing = []
        world.now = world.now.addingTimeInterval(Sender.failureLifetime + 1)
        guard case .rewritten = try await world.encode("t29-second") else {
            Issue.record("The old failure was returned.")
            return
        }
    }

    @Test func deletesTheUploadsWhenMailDropTakesOver() async throws {
        let world = World()
        _ = try await world.encode("t29-first")
        let folder = try #require(world.nextcloud.folders.first { $0.hasPrefix("Mail/2026") })
        // Mail Drop's second call has the files removed, and its third has the header (docs/MAIL.md).
        #expect(try await world.encode("t34-second") == .unchanged)
        #expect(world.nextcloud.deleted == [folder])
        let text = try #require(String(bytes: try Fixture.data("t29-second"), encoding: .utf8))
        let mailDrop = Data(("Remote-Attachment-Url: https://www.icloud.com/attachment/?u=x\n" + text).utf8)
        #expect(await world.encode(mailDrop) == .unchanged)
        #expect(world.nextcloud.uploads == 2)
    }

    @Test func keepsSignatureImagesFromTheFirstCall() async throws {
        let world = World()
        _ = try await world.encode("t30-first")
        guard case .rewritten(let data) = try await world.encode("t30-second") else {
            Issue.record("The second call wasn't rewritten.")
            return
        }
        #expect(MimeMessage(data).files.map(\.filename) == ["Screenshot 2026-11-05 at 22.00.04.png"])
        #expect(world.nextcloud.uploads == 2)
    }

    @Test func runsCallsForOneMessageOneAtATime() async throws {
        let world = World()
        let first = try Fixture.data("t29-first")
        let second = try Fixture.data("t29-second")
        // One reference before the calls: two calls reaching the lazy property at once could each make a sender.
        let sender = world.sender
        async let one = sender.encode(first, isAutoSave: false, contextID: UUID())
        async let two = sender.encode(second, isAutoSave: false, contextID: UUID())
        let results = await [one, two]
        #expect(results.allSatisfy { if case .rewritten = $0 { true } else { false } })
        #expect(world.nextcloud.uploads == 2)
        #expect(world.nextcloud.shares.count == 1)
    }

    @Test func keepsSignatureImagesThatLoseTheirContentIDs() async throws {
        let world = World()
        guard case .rewritten(let first) = try await world.encode("signature-file-first") else {
            Issue.record("The first call wasn't rewritten.")
            return
        }
        #expect(MimeMessage(first).files.map(\.filename) == ["Screenshot 2026-11-05 at 22.00.04.png"])
        let second = try Fixture.message("signature-file-second")
        #expect(second.files.allSatisfy { $0.contentID == nil })
        guard case .rewritten(let data) = try await world.encode("signature-file-second") else {
            Issue.record("The second call wasn't rewritten.")
            return
        }
        #expect(MimeMessage(data).files.map(\.filename) == ["Screenshot 2026-11-05 at 22.00.04.png"])
        #expect(world.nextcloud.uploads == 1)
    }

    @Test func keepsMessagesApart() async throws {
        let world = World()
        _ = try await world.encode("t29-second")
        _ = await world.encode(try SendFixtures.message("t29-second", id: "00000000-0000-4000-8000-000000000002"))
        #expect(world.nextcloud.uploads == 4)
        #expect(world.nextcloud.folders.filter { $0.hasPrefix("Mail/2026") }.count == 2)
    }
}
