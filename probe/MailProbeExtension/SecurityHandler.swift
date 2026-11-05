import CryptoKit
import Foundation
import MailKit

let maxDumpBytes = 32_000_000
private let calls = CallCounter()

/// Mail calls `encode` several times for one message, so calls are numbered per message.
private final class CallCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var callsByMessage: [String: Int] = [:]
    private var delayedMessages: Set<String> = []
    private var sequence = 0

    func next(for message: String) -> (call: Int, sequence: Int) {
        lock.lock()
        defer { lock.unlock() }
        callsByMessage[message, default: 0] += 1
        sequence += 1
        return (callsByMessage[message]!, sequence)
    }

    func claimDelay(for message: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return delayedMessages.insert(message).inserted
    }
}

final class SecurityHandler: NSObject, MEMessageSecurityHandler {
    static let shared = SecurityHandler()

    // MARK: - Encoding

    func getEncodingStatus(for message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void) {
        let directive = ProbeDirective(subject: message.subject)
        let canEncode = !(directive?.reportsCannotEncode ?? false)

        var fields = contextFields(message, composeContext)
        fields["marker"] = directive?.text
        fields["reportedCanEncode"] = canEncode
        ProbeLog.event("status", fields)

        completionHandler(MEOutgoingMessageEncodingStatus(canSign: canEncode, canEncrypt: canEncode, securityError: nil, addressesFailingEncryption: []))
    }

    func encode(_ message: MEMessage, composeContext: MEComposeContext, completionHandler: @escaping (MEMessageEncodingResult) -> Void) {
        var fields = contextFields(message, composeContext)
        guard let directive = ProbeDirective(subject: message.subject) else {
            ProbeLog.event("encode-unmarked", fields)
            completionHandler(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
            return
        }
        fields["marker"] = directive.text

        guard let raw = message.rawData else {
            ProbeLog.event("encode-no-raw-data", fields)
            completionHandler(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
            return
        }

        let contextID = composeContext.contextID.uuidString
        // Decided by state, not headers: X-Apple-Auto-Saved was missing on 7 of 30 drafts, and every draft had
        // X-Apple-Mail-Remote-Attachments, which a Mail Drop send (t31) might carry too.
        let isAutoSave = message.state == .draft
        DispatchQueue.global(qos: .userInitiated).async {
            handleMarkedMessage(raw, directive: directive, contextID: contextID, isAutoSave: isAutoSave, fields: fields, completion: completionHandler)
        }
    }

    // MARK: - Decoding

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        if data.prefix(65_536).range(of: Data("X-MailProbe".utf8)) != nil {
            ProbeLog.event("decode-called", ["bytes": data.count])
        }
        return nil
    }

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? { nil }

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? { nil }

    func primaryActionClicked(forMessageContext context: Data, completionHandler: @escaping (MEExtensionViewController?) -> Void) {
        completionHandler(nil)
    }
}

private func handleMarkedMessage(_ raw: Data, directive: ProbeDirective, contextID: String, isAutoSave: Bool, fields: [String: Any], completion: @escaping (MEMessageEncodingResult) -> Void) {
    let started = Date()
    let message = MimeMessage(raw)
    let headers = message.root.headers
    let messageID = headers["x-universally-unique-identifier"] ?? contextID
    PopoverPasswords.shared.link(context: contextID, toMessage: messageID)
    let (call, sequence) = calls.next(for: messageID)
    let dumpPrefix = String(format: "%04d-call%d", sequence, call)

    var details = fields
    details["messageID"] = messageID
    details["call"] = call
    details["sequence"] = sequence
    details["isAutoSave"] = isAutoSave
    details["usesCRLF"] = message.usesCRLF
    details["sha256"] = SHA256.hash(data: raw).map { String(format: "%02x", $0) }.joined()
    details["headerNames"] = message.root.headerNames
    details["structure"] = message.structure
    ProbeLog.event("encode-marked", details)
    if raw.count <= maxDumpBytes { ProbeLog.dump(raw, named: "\(dumpPrefix)-in.eml") }

    if isAutoSave {
        ProbeLog.event("encode-skipped-autosave", ["sequence": sequence])
        completion(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
        return
    }

    let delay = calls.claimDelay(for: messageID) ? directive.delaySeconds : 0
    if delay > 0 { ProbeLog.event("delay-start", ["sequence": sequence, "seconds": delay]) }

    DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + .seconds(delay)) {
        if delay > 0 { ProbeLog.event("delay-end", ["sequence": sequence, "seconds": delay]) }

        var outcome: [String: Any] = ["sequence": sequence, "call": call, "action": String(describing: directive.action)]
        let result: MEMessageEncodingResult
        switch directive.action {
        case .logOnly:
            result = MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        case .failSigning:
            result = MEMessageEncodingResult(encodedMessage: nil, signingError: probeError("signing"), encryptionError: nil)
        case .failEncryption:
            result = MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: probeError("encryption"))
        case let .rewrite(isSigned, isEncrypted):
            var note = "\(directive.text) call=\(call)"
            let popoverFiles = PopoverFiles.shared.urls(for: contextID)
            if !popoverFiles.isEmpty {
                ProbeLog.event("popover-files-at-encode", ["sequence": sequence, "call": call, "files": popoverFileFields(popoverFiles)])
                let names = popoverFiles.map { $0.lastPathComponent.unicodeScalars.map { $0.isASCII ? String($0) : "?" }.joined() }
                note += " popover=\(names.joined(separator: ","))"
            }
            if let found = PopoverPasswords.shared.password(for: contextID, message: messageID) {
                ProbeLog.event("popover-password-at-encode", ["sequence": sequence, "call": call, "characters": found.password.count, "viaMessageID": found.viaMessageID])
                note += " password=\(found.password.count)chars" + (found.viaMessageID ? " via-message-id" : "")
            }
            let rewrite = message.rewritten(note: note, removingOver: directive.removalLimitBytes)
            outcome["strippedParts"] = rewrite.stripped.map { "\($0.filename) \($0.contentType) \($0.encodedBytes)B" }
            outcome["notedPlain"] = rewrite.notedPlain
            outcome["notedHTML"] = rewrite.notedHTML
            outcome["returnedBytes"] = rewrite.data.count
            ProbeLog.dump(rewrite.data, named: "\(dumpPrefix)-out.eml")
            let encoded = MEEncodedOutgoingMessage(rawData: rewrite.data, isSigned: isSigned, isEncrypted: isEncrypted)
            result = MEMessageEncodingResult(encodedMessage: encoded, signingError: nil, encryptionError: nil)
        }

        outcome["elapsedSeconds"] = Date().timeIntervalSince(started)
        ProbeLog.event("encode-finished", outcome)
        completion(result)
    }
}

private func probeError(_ kind: String) -> NSError {
    NSError(domain: "lv.warp.mailprobe", code: 1, userInfo: [NSLocalizedDescriptionKey: "MailProbe test: simulated \(kind) failure. The message should not have been sent."])
}
