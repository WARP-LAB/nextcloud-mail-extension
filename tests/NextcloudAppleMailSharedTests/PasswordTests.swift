import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The email's password from the toolbar popover (FR7, R8).
struct MessagePasswordsTests {
    let message = "00000000-0000-4000-8000-000000000001"

    @Test func findsThePasswordOfAReopenedDraft() {
        let vault = MemoryVault()
        let passwords = MessagePasswords(vault: vault)
        let first = UUID()
        passwords.set("correct horse battery", context: first)
        #expect(vault.kept.isEmpty)
        passwords.link(context: first, message: message)
        #expect(vault.kept[message] == "correct horse battery")
        // A reopened draft has a new context, linked at its first auto-save.
        let reopened = UUID()
        #expect(passwords.shown(context: reopened) == "")
        passwords.link(context: reopened, message: message)
        #expect(passwords.password(context: reopened, message: message) == "correct horse battery")
        #expect(passwords.shown(context: reopened) == "correct horse battery")
    }

    @Test func keepsThePasswordWhenMailRestarts() {
        let vault = MemoryVault()
        let before = MessagePasswords(vault: vault)
        let context = UUID()
        before.link(context: context, message: message)
        before.set("correct horse battery", context: context)
        let after = MessagePasswords(vault: vault)
        #expect(after.password(context: UUID(), message: message) == "correct horse battery")
    }

    @Test func clearingThePasswordRemovesItsCopy() {
        let vault = MemoryVault()
        let passwords = MessagePasswords(vault: vault)
        let context = UUID()
        passwords.link(context: context, message: message)
        passwords.set("correct horse battery", context: context)
        passwords.set("", context: context)
        #expect(vault.kept.isEmpty)
        #expect(passwords.password(context: context, message: message) == nil)
        vault.kept[message] = "older"
        #expect(passwords.password(context: context, message: message) == nil, "the cleared field wins")
    }

    @Test func forgetsAMessage() {
        let vault = MemoryVault()
        let passwords = MessagePasswords(vault: vault)
        let context = UUID()
        passwords.link(context: context, message: message)
        passwords.set("correct horse battery", context: context)
        passwords.forget(message: message)
        #expect(vault.kept.isEmpty)
        #expect(passwords.password(context: context, message: message) == nil)
    }

    @Test func readsAHeaderWithoutTheBody() throws {
        let data = try Fixture.data("t15-first")
        #expect(MimePart.headerField("x-universally-unique-identifier", in: data) == message)
        #expect(MimePart.headerField("subject", in: data) == "[probe ff] t15")
        #expect(MimePart.headerField("content-transfer-encoding", in: data) == nil)
        let folded = Data("Subject: a\r\n b\r\nTo: c\r\n\r\nSubject: body".utf8)
        #expect(MimePart.headerField("subject", in: folded) == "a b")
        let bodyOnly = Data("To: c\r\n\r\nText\n\nX-Universally-Unique-Identifier: not a header".utf8)
        #expect(MimePart.headerField("x-universally-unique-identifier", in: bodyOnly) == nil)
    }
}

struct SendPasswordTests {
    final class World {
        let nextcloud = FakeNextcloud()
        let vault = MemoryVault()
        lazy var passwords = MessagePasswords(vault: vault)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)

        func sender() -> Sender {
            Sender(
                Sender.Dependencies(
                    settings: { SendFixtures.settings() },
                    connect: { [unowned self] in nextcloud },
                    store: UploadLedgerStore(url: folder.appendingPathComponent("upload-ledger.json")),
                    passwords: passwords,
                    now: { SendFixtures.today }
                ))
        }

        deinit {
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func text(_ result: SendResult) throws -> String {
        guard case .rewritten(let data) = result else {
            Issue.record("Not rewritten: \(result)")
            return ""
        }
        return MimeMessage(data).text("plain").joined() + MimeMessage(data).text("html").joined()
    }

    @Test func givesTheSharesThePasswordAndSaysSoInTheEmail() async throws {
        let world = World()
        let sender = world.sender()
        let context = UUID()
        world.passwords.set("correct horse battery", context: context)
        let first = try text(await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context))
        let second = try text(
            await sender.encode(try Fixture.data("t29-second"), isAutoSave: false, contextID: context))
        #expect(world.nextcloud.shares.map(\.password) == ["correct horse battery"])
        #expect(world.nextcloud.passwordChanges.isEmpty, "the second call finds the shares already have it")
        for body in [first, second] {
            #expect(body.contains(LinkText.passwordNotice))
            #expect(!body.contains("correct horse battery"))
        }
    }

    @Test func findsThePasswordTypedBeforeAnAutoSaveInAReopenedDraft() async throws {
        let world = World()
        let sender = world.sender()
        let typed = UUID()
        world.passwords.set("correct horse battery", context: typed)
        _ = await sender.encode(try Fixture.data("t29-first"), isAutoSave: true, contextID: typed)
        _ = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: UUID())
        #expect(world.nextcloud.shares.map(\.password) == ["correct horse battery"])
    }

    @Test func changesTheSharesPasswordAfterUndoSend() async throws {
        let world = World()
        let sender = world.sender()
        let context = UUID()
        world.passwords.set("correct horse battery", context: context)
        _ = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        // Undo Send gives a new context, where another password is typed.
        let again = UUID()
        _ = await sender.encode(try Fixture.data("t29-first"), isAutoSave: true, contextID: again)
        world.passwords.set("staple battery horse", context: again)
        _ = await sender.encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: again)
        #expect(world.nextcloud.shares.count == 1)
        #expect(world.nextcloud.passwordChanges == [["1", "staple battery horse"]])
        world.passwords.set("", context: again)
        let body = try text(await sender.encode(try Fixture.data("t29-second"), isAutoSave: false, contextID: again))
        #expect(world.nextcloud.passwordChanges.last == ["1", ""])
        #expect(!body.contains(LinkText.passwordNotice))
    }

    @Test func setsThePasswordAgainAfterMailRestarts() async throws {
        let world = World()
        let context = UUID()
        world.passwords.set("correct horse battery", context: context)
        _ = await world.sender().encode(try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        // A new process doesn't know what the shares have, so it gives them the password again.
        _ = await world.sender().encode(try Fixture.data("t29-second"), isAutoSave: false, contextID: context)
        #expect(world.nextcloud.passwordChanges == [["1", "correct horse battery"]])
    }

    @Test func stopsWhenThePolicyRejectsThePasswordOrTheServerRequiresOne() async throws {
        let world = World()
        world.nextcloud.limits.passwordEnforced = true
        let result = await world.sender().encode(try Fixture.data("t29-second"), isAutoSave: false, contextID: UUID())
        #expect(result == .failed(SendError.passwordRequired.localizedDescription))
    }
}
