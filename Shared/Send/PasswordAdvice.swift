import Foundation

/// The server's password policy, as the toolbar popover uses it (FR7, T16).
protocol PasswordPolicyService {
    func passwordProblem(_ password: String) async throws -> String?
    func generatedPassword() async throws -> String
}

extension NextcloudClient: PasswordPolicyService {}

/// What the toolbar popover says about an email's password, and the password its Generate button suggests (T16).
/// Neither ever logs or stores the password.
enum PasswordAdvice {
    /// Letters and digits without the ones that are easy to confuse, such as 0 and O, or 1, l and I.
    static let alphabet = Array("abcdefghijkmnopqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    /// The server's reason for refusing the password, or nil when it accepts it, when the password is empty, or when
    /// the server can't check it. The send then finds out, as before (FR7).
    static func problem(with password: String, server: PasswordPolicyService?) async -> String? {
        guard !password.isEmpty, let server else {
            return nil
        }
        return try? await server.passwordProblem(password)
    }

    /// A password the server's policy accepts, or a local one when the server can't make one.
    static func generated(by server: PasswordPolicyService?) async -> String {
        if let server, let password = try? await server.generatedPassword(), !password.isEmpty {
            return password
        }
        return local()
    }

    /// A random password from `alphabet`, with at least one lower-case letter, one upper-case letter and one digit.
    static func local(length: Int = 16) -> String {
        var generator = SystemRandomNumberGenerator()
        return local(length: length, using: &generator)
    }

    static func local<Generator: RandomNumberGenerator>(length: Int, using generator: inout Generator) -> String {
        while true {
            let password = String((0..<max(length, 3)).map { _ in alphabet.randomElement(using: &generator) ?? "a" })
            if password.contains(where: \.isLowercase) && password.contains(where: \.isUppercase)
                && password.contains(where: \.isNumber)
            {
                return password
            }
        }
    }

    /// A client for the account in the shared Keychain item, or nil when nobody is logged in or the server can't be
    /// reached.
    static func sharedServer() async -> NextcloudClient? {
        guard let group = SharedStorage.appGroupIdentifier, let account = try? Credentials(group: group).load() else {
            return nil
        }
        return try? await NextcloudClient.connect(account)
    }
}
