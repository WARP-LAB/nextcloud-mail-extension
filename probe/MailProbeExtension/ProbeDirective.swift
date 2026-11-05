import Foundation

/// Test instructions typed into the subject line, for example `[probe ff delay=30] my test`.
/// Mail without a marker is never modified or dumped.
struct ProbeDirective {
    enum Action: Equatable {
        case logOnly
        case rewrite(isSigned: Bool, isEncrypted: Bool)
        case failSigning
        case failEncryption
    }

    let text: String
    private(set) var action = Action.logOnly
    private(set) var delaySeconds = 0
    private(set) var reportsCannotEncode = false
    private(set) var blocksSend = false
    private(set) var removalLimitBytes: Int?

    init?(subject: String) {
        guard let marker = subject.range(of: #"\[probe\b[^\]]*\]"#, options: [.regularExpression, .caseInsensitive]) else {
            return nil
        }
        let tokens = subject[marker].dropFirst(6).dropLast().lowercased().split(separator: " ")
        text = tokens.joined(separator: " ")

        for token in tokens {
            switch token {
            case "log": action = .logOnly
            case "ff": action = .rewrite(isSigned: false, isEncrypted: false)
            case "tf": action = .rewrite(isSigned: true, isEncrypted: false)
            case "ft": action = .rewrite(isSigned: false, isEncrypted: true)
            case "tt": action = .rewrite(isSigned: true, isEncrypted: true)
            case "errs": action = .failSigning
            case "erre": action = .failEncryption
            case "nostatus": reportsCannotEncode = true
            case "block": blocksSend = true
            default:
                if token.hasPrefix("delay="), let seconds = Int(token.dropFirst(6)), seconds >= 0 {
                    delaySeconds = seconds
                } else if token.hasPrefix("min="), let megabytes = Int(token.dropFirst(4)), megabytes >= 0 {
                    removalLimitBytes = megabytes * 1_000_000
                }
            }
        }
    }
}
