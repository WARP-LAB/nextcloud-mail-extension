import Foundation
import Testing

@testable import NextcloudMailExtensionShared

struct SharedStorageTests {
    @Test func readsTheAppGroupIdentifier() {
        let info = [SharedStorage.infoKey: "ABCDE12345.lv.warp.nextcloudmailextension"]
        #expect(SharedStorage.appGroupIdentifier(in: info) == "ABCDE12345.lv.warp.nextcloudmailextension")
    }

    @Test(arguments: [
        [:],
        [SharedStorage.infoKey: ""],
        [SharedStorage.infoKey: "$(TeamIdentifierPrefix)lv.warp.nextcloudmailextension"],
    ])
    func rejectsMissingOrUnexpandedIdentifiers(info: [String: String]) {
        #expect(SharedStorage.appGroupIdentifier(in: info) == nil)
    }

    @Test func passesOnlyWhenAllThreeStoresWork() {
        let passing = StorageCheck.Result(container: "ok: a", settings: "ok: a", keychain: "ok: a")
        let failing = StorageCheck.Result(container: "ok: a", settings: "ok: a", keychain: "failed: no access")
        #expect(passing.passed)
        #expect(!failing.passed)
    }

    @Test func encodesTheResultAsJSON() throws {
        let result = StorageCheck.Result(container: "ok: a", settings: "failed: b", keychain: "ok: c")
        let decoded = try JSONDecoder().decode(StorageCheck.Result.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }
}
