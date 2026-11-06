import Foundation
import Testing

@testable import NextcloudAppleMailShared

/// The email's password from the toolbar popover (FR7, R8).
struct MessageValuesTests {
    let message = "00000000-0000-4000-8000-000000000001"

    @Test func findsThePasswordOfAReopenedDraft() {
        let vault = MemoryVault()
        let passwords = MessageValues(vault: vault)
        let first = UUID()
        passwords.set("correct horse battery", context: first)
        #expect(vault.kept.isEmpty)
        passwords.link(context: first, message: message)
        #expect(vault.kept[message] == "correct horse battery")
        // A reopened draft has a new context, linked at its first auto-save.
        let reopened = UUID()
        #expect(passwords.shown(context: reopened) == "")
        passwords.link(context: reopened, message: message)
        #expect(passwords.value(context: reopened, message: message) == "correct horse battery")
        #expect(passwords.shown(context: reopened) == "correct horse battery")
    }

    @Test func keepsThePasswordWhenMailRestarts() {
        let vault = MemoryVault()
        let before = MessageValues(vault: vault)
        let context = UUID()
        before.link(context: context, message: message)
        before.set("correct horse battery", context: context)
        let after = MessageValues(vault: vault)
        #expect(after.value(context: UUID(), message: message) == "correct horse battery")
    }

    @Test func clearingThePasswordRemovesItsCopy() {
        let vault = MemoryVault()
        let passwords = MessageValues(vault: vault)
        let context = UUID()
        passwords.link(context: context, message: message)
        passwords.set("correct horse battery", context: context)
        passwords.set("", context: context)
        #expect(vault.kept.isEmpty)
        #expect(passwords.value(context: context, message: message) == nil)
        vault.kept[message] = "older"
        #expect(passwords.value(context: context, message: message) == nil, "the cleared field wins")
    }

    @Test func forgetsAMessage() {
        let vault = MemoryVault()
        let passwords = MessageValues(vault: vault)
        let context = UUID()
        passwords.link(context: context, message: message)
        passwords.set("correct horse battery", context: context)
        passwords.forget(message: message)
        #expect(vault.kept.isEmpty)
        #expect(passwords.value(context: context, message: message) == nil)
    }

    @Test func dropsCopiesAsOldAsTheLedgersEntries() {
        let vault = MemoryVault()
        let passwords = MessageValues(vault: vault)
        vault.now = SendFixtures.today.addingTimeInterval(-UploadLedger.lifetime - 60)
        passwords.link(context: UUID(), message: "old")
        passwords.set("old password", context: UUID())
        let old = UUID()
        passwords.link(context: old, message: "old")
        passwords.set("old password", context: old)
        vault.now = SendFixtures.today
        let recent = UUID()
        passwords.link(context: recent, message: "recent")
        passwords.set("recent password", context: recent)
        passwords.prune(now: SendFixtures.today)
        #expect(vault.kept == ["recent": "recent password"])
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
        lazy var passwords = MessageValues(vault: vault)
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

/// An email's own link expiry, set in the popover (FR4).
struct SendExpiryTests {
    func encoded(_ expiry: LinkExpiry) throws -> String {
        try #require(String(bytes: JSONEncoder().encode(expiry), encoding: .utf8))
    }

    @Test func givesTheSharesTheEmailsOwnExpiryAndFollowsItsChanges() async throws {
        let nextcloud = FakeNextcloud()
        let expiries = MessageValues(vault: MemoryVault())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.removeItem(at: folder)
        }
        let sender = Sender(
            Sender.Dependencies(
                settings: { SendFixtures.settings() },
                connect: { nextcloud },
                store: UploadLedgerStore(url: folder.appendingPathComponent("upload-ledger.json")),
                expiries: expiries,
                now: { SendFixtures.today }
            ))
        let context = UUID()
        expiries.set(try encoded(.year), context: context)
        guard
            case .rewritten(let first) = await sender.encode(
                try Fixture.data("t29-first"), isAutoSave: false, contextID: context)
        else {
            Issue.record("Not rewritten.")
            return
        }
        #expect(nextcloud.shares.map(\.expireDate) == ["2027-11-06"])
        #expect(MimeMessage(first).text("html").joined().contains("link expires 6 Nov 2027"))
        // After Undo Send, the email gets another expiry.
        expiries.set(try encoded(.days(3)), context: context)
        guard
            case .rewritten(let second) = await sender.encode(
                try Fixture.data("t29-second"), isAutoSave: false, contextID: context)
        else {
            Issue.record("Not rewritten.")
            return
        }
        #expect(nextcloud.shares.count == 1)
        #expect(nextcloud.expiryChanges == [["1", "2026-11-09"]])
        #expect(MimeMessage(second).root.text?.contains("link expires 9 Nov 2026") == true)
        _ = await sender.encode(try Fixture.data("t29-second"), isAutoSave: false, contextID: context)
        #expect(nextcloud.expiryChanges.count == 1, "a call with the same expiry changes nothing")
    }

    @Test(arguments: [
        (LinkExpiry.week, "in a week"), (.month, "in a month"), (.year, "in a year"), (.never, "never"),
        (.days(14), "after 14 days"),
        (
            .after(LinkExpiry.Period(months: 2, days: 3, hours: 1)),
            "after 2 months, 3 days and 1 hour"
        ),
        (.after(LinkExpiry.Period()), "at the end of the day of sending"),
    ])
    func describesTheExpiry(expiry: LinkExpiry, text: String) {
        #expect(expiry.description == text)
    }
}
