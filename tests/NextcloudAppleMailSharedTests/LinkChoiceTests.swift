import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The toolbar popover's choice of which of an email's files become links (FR3).
struct LinkChoiceTests {
    final class World {
        let nextcloud = FakeNextcloud()
        let passwords = MessageValues(vault: MemoryVault())
        let choices = MessageValues(vault: MemoryVault())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var settings = SendFixtures.settings()

        func sender() -> Sender {
            Sender(
                Sender.Dependencies(
                    settings: { [unowned self] in settings },
                    connect: { [unowned self] in nextcloud },
                    store: UploadLedgerStore(url: folder.appendingPathComponent("upload-ledger.json")),
                    passwords: passwords,
                    linkChoices: choices,
                    now: { SendFixtures.today }
                ))
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    @Test func readsTheStoredChoice() {
        #expect(LinkChoice(stored: nil) == .useSettings)
        #expect(LinkChoice(stored: "") == .useSettings)
        #expect(LinkChoice(stored: "somethingNew") == .useSettings)
        #expect(LinkChoice(stored: "allFiles") == .allFiles)
        #expect(LinkChoice(stored: "keepAttached") == .keepAttached)
    }

    @Test func turnsTheChoiceIntoARule() throws {
        var settings = Settings()
        settings.onlyLargeFiles = true
        settings.sizeLimitMegabytes = 5
        settings.pastedImagesBecomeLinks = false
        #expect(settings.linkPolicy(for: .useSettings).rule == .largerThan(bytes: 5_000_000))
        #expect(!settings.linkPolicy(for: .useSettings).pastedImagesBecomeLinks)
        let all = settings.linkPolicy(for: .allFiles)
        #expect(all.rule == .allAttachments)
        #expect(all.pastedImagesBecomeLinks)
        #expect(settings.linkPolicy(for: .keepAttached).rule == .noFiles)
        let message = try Fixture.message("t27-second")
        #expect(LinkPolicy(rule: .noFiles).linkedFiles(in: message, signatureContentIDs: []).isEmpty)
    }

    @Test func linksEveryFileButTheSignaturesWhateverTheSettings() async throws {
        let world = World()
        world.settings.onlyLargeFiles = true
        world.settings.sizeLimitMegabytes = 1000
        world.settings.pastedImagesBecomeLinks = false
        let sender = world.sender()
        let context = UUID()
        world.choices.set(LinkChoice.allFiles.rawValue, context: context)
        guard
            case .rewritten(let data) = await sender.encode(
                try Fixture.data("t30-first"), isAutoSave: false, contextID: context)
        else {
            Issue.record("Not rewritten.")
            return
        }
        let names = world.nextcloud.files.keys.map { ($0 as NSString).lastPathComponent }.sorted()
        #expect(names == ["PastedGraphic-1.png", "dummy-1MB.png"])
        #expect(MimeMessage(data).files.count == 1, "the signature's image stays")
    }

    @Test func keepsEveryFileAttached() async throws {
        let world = World()
        let context = UUID()
        world.choices.set(LinkChoice.keepAttached.rawValue, context: context)
        let result = await world.sender().encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        #expect(result == .unchanged)
        #expect(world.nextcloud.uploads == 0)
    }

    @Test func removesTheLinksButKeepsThePopoversValuesWhenFilesAreKeptAfterUndoSend() async throws {
        let world = World()
        let sender = world.sender()
        let context = UUID()
        world.passwords.set("correct horse battery", context: context)
        let first = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        #expect(first != .unchanged)
        #expect(world.nextcloud.uploads > 0)
        // After Undo Send, the user keeps the files attached.
        world.choices.set(LinkChoice.keepAttached.rawValue, context: context)
        let again = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        #expect(again == .unchanged)
        #expect(world.nextcloud.deleted.count == 1, "the email's folder is deleted")
        #expect(world.passwords.value(context: context, message: nil) == "correct horse battery")
        #expect(world.choices.value(context: context, message: nil) == LinkChoice.keepAttached.rawValue)
    }

    @Test func warnsWithSignOffOnlyAboutTheFilesTheChoiceLinks() throws {
        let message = try Fixture.message("t15-first")
        var settings = Settings()
        settings.onlyLargeFiles = true
        settings.sizeLimitMegabytes = 1000
        #expect(SendWarnings.warning(for: message, signOn: false, settings: settings, linkedEarlier: 0) == nil)
        let all = SendWarnings.warning(
            for: message, signOn: false, settings: settings, linkedEarlier: 0, choice: .allFiles)
        #expect(all?.contains("“dummy-1MB.bin”") == true)
        settings.onlyLargeFiles = false
        let kept = SendWarnings.warning(
            for: message, signOn: false, settings: settings, linkedEarlier: 0, choice: .keepAttached)
        #expect(kept == nil)
    }
}
