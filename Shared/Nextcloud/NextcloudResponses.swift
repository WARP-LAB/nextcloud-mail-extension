import Foundation

// The bodies of Nextcloud's responses, as NextcloudClient reads them (docs/NEXTCLOUD.md).

struct OCSEnvelope<T: Decodable>: Decodable {
    struct Body: Decodable {
        let meta: Meta
        let data: T
    }

    struct Meta: Decodable {
        let statuscode: Int
        let message: String?
    }

    let ocs: Body
}

/// Any JSON value, for responses whose data isn't needed.
struct Ignored: Decodable {
    init(from decoder: Decoder) throws {}
}

/// An integer that some Nextcloud versions send as a string.
struct LenientInt: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let number = try? container.decode(Int.self) {
            value = number
        } else {
            value = (try? container.decode(String.self)).flatMap { Int($0) }
        }
    }
}

struct UserData: Decodable {
    let id: String
}

struct AppPasswordData: Decodable {
    let apppassword: String
}

struct ShareData: Decodable {
    let id: String
    let url: String
    let expiration: String?

    enum CodingKeys: String, CodingKey {
        case id, url, expiration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let text = try? container.decode(String.self, forKey: .id) {
            id = text
        } else {
            id = String(try container.decode(Int.self, forKey: .id))
        }
        url = try container.decode(String.self, forKey: .url)
        expiration = try container.decodeIfPresent(String.self, forKey: .expiration)
    }

    func share() throws -> Share {
        guard let link = URL(string: url) else {
            throw NextcloudError.invalidResponse("the new share")
        }
        return Share(id: id, url: link, expiration: expiration.flatMap { ExpiryDate(server: $0) })
    }
}

struct CapabilitiesData: Decodable {
    struct Version: Decodable {
        let string: String
    }

    struct Capabilities: Decodable {
        let filesSharing: FilesSharing?
    }

    struct FilesSharing: Decodable {
        let `public`: Public?
    }

    struct Public: Decodable {
        let password: Password?
        let expireDate: ExpireDate?
    }

    struct Password: Decodable {
        let enforced: Bool?
    }

    struct ExpireDate: Decodable {
        let enabled: Bool?
        let days: LenientInt?
        let enforced: Bool?
    }

    let version: Version
    let capabilities: Capabilities

    var limits: SharingLimits {
        let links = capabilities.filesSharing?.public
        let expiry = links?.expireDate
        let enabled = expiry?.enabled ?? false
        return SharingLimits(
            version: version.string,
            passwordEnforced: links?.password?.enforced ?? false,
            defaultExpiryDays: enabled ? expiry?.days?.value : nil,
            expiryEnforced: enabled && (expiry?.enforced ?? false)
        )
    }
}

/// The password policy app's answer to `validate`: `passed`, and the reason when it didn't.
struct PasswordCheckData: Decodable {
    let passed: Bool
    let reason: String?
}

/// The password policy app's answer to `generate`.
struct GeneratedPasswordData: Decodable {
    let password: String
}

struct LoginFlowData: Decodable {
    struct Poll: Decodable {
        let token: String
        let endpoint: String
    }

    let poll: Poll
    let login: String
}

struct LoginResultData: Decodable {
    let server: String
    let loginName: String
    let appPassword: String
}
