import Foundation
import Testing

@testable import NextcloudMailExtensionShared

/// What the toolbar popover says about an email's password, and the password it generates (T16).
struct PasswordAdviceTests {
    /// A server whose password policy refuses passwords shorter than 10 characters, or that can't answer.
    struct FakePolicy: PasswordPolicyService {
        var fails = false
        var generated = "Kx7mPq2wZr"

        func passwordProblem(_ password: String) async throws -> String? {
            if fails {
                throw NextcloudError.notFound("The password policy app")
            }
            return password.count < 10 ? "Password needs to be at least 10 characters long." : nil
        }

        func generatedPassword() async throws -> String {
            if fails {
                throw NextcloudError.notFound("The password policy app")
            }
            return generated
        }
    }

    /// The same numbers every run, so that a test of the local generator repeats.
    struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var mixed = state
            mixed = (mixed ^ (mixed >> 30)) &* 0xBF58_476D_1CE4_E5B9
            mixed = (mixed ^ (mixed >> 27)) &* 0x94D0_49BB_1331_11EB
            return mixed ^ (mixed >> 31)
        }
    }

    @Test func givesTheServersReasonOnlyWhenItRefusesThePassword() async {
        let server = FakePolicy()
        #expect(
            await PasswordAdvice.problem(with: "short", server: server)
                == "Password needs to be at least 10 characters long.")
        #expect(await PasswordAdvice.problem(with: "long enough now", server: server) == nil)
        #expect(await PasswordAdvice.problem(with: "", server: server) == nil, "no password, nothing to say")
    }

    @Test func saysNothingWhenTheServerCantCheck() async {
        #expect(await PasswordAdvice.problem(with: "short", server: FakePolicy(fails: true)) == nil)
        #expect(await PasswordAdvice.problem(with: "short", server: nil) == nil, "nobody logged in")
    }

    @Test func generatesWithTheServerOrLocally() async {
        #expect(await PasswordAdvice.generated(by: FakePolicy()) == "Kx7mPq2wZr")
        let servers: [PasswordPolicyService?] = [FakePolicy(fails: true), FakePolicy(generated: ""), nil]
        for server in servers {
            let password = await PasswordAdvice.generated(by: server)
            #expect(password.count == 16)
        }
    }

    @Test func generatesLocalPasswordsFromTheAlphabetWithEveryKindOfCharacter() {
        var generator = SeededGenerator(state: 1)
        var seen = Set<String>()
        for _ in 0..<200 {
            let password = PasswordAdvice.local(length: 16, using: &generator)
            #expect(password.count == 16)
            let fromAlphabet = password.allSatisfy { PasswordAdvice.alphabet.contains($0) }
            let everyKind =
                password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase)
                && password.contains(where: \.isNumber)
            #expect(fromAlphabet)
            #expect(everyKind)
            seen.insert(password)
        }
        #expect(seen.count == 200, "no repeats")
        let confusable = PasswordAdvice.alphabet.contains { "0O1lI".contains($0) }
        #expect(!confusable)
        #expect(PasswordAdvice.local(length: 1).count == 3, "long enough for every kind")
    }

    @Test func readsThePasswordPolicyAppsAnswers() throws {
        let refused = Data(
            (#"{"ocs":{"meta":{"status":"ok","statuscode":200,"message":"OK"},"data":{"passed":false,"#
                + #""reason":"Password needs to be at least 10 characters long."}}}"#).utf8)
        let check = try NextcloudClient.ocsData(PasswordCheckData.self, from: refused, status: 200)
        #expect(!check.passed && check.reason == "Password needs to be at least 10 characters long.")
        let passed = Data(#"{"ocs":{"meta":{"status":"ok","statuscode":200},"data":{"passed":true}}}"#.utf8)
        #expect(try NextcloudClient.ocsData(PasswordCheckData.self, from: passed, status: 200).passed)
        let generated = Data(
            #"{"ocs":{"meta":{"status":"ok","statuscode":200},"data":{"password":"Kx7mPq2wZr"}}}"#.utf8)
        #expect(
            try NextcloudClient.ocsData(GeneratedPasswordData.self, from: generated, status: 200).password
                == "Kx7mPq2wZr")
    }
}
