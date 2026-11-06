import MailKit

/// Reports that the extension can sign but not encrypt, so Mail offers the Sign button, which is the upload switch
/// (docs/MAIL.md). `encode` hands each call to the `Sender`, which uploads the files and puts links in their place.
final class SecurityHandler: NSObject, MEMessageSecurityHandler {
    static let shared = SecurityHandler()

    private let sender = Sender(
        Sender.Dependencies(
            settings: {
                SharedStorage.appGroupIdentifier.flatMap(SettingsStore.init(groupIdentifier:))?.load() ?? Settings()
            },
            connect: {
                guard let group = SharedStorage.appGroupIdentifier,
                    let account = try Credentials(group: group).load()
                else {
                    return nil
                }
                return try await NextcloudClient.connect(account)
            },
            store: UploadLedgerStore.inContainer
        ))

    // MARK: - Encoding

    func getEncodingStatus(
        for message: MEMessage,
        composeContext: MEComposeContext,
        completionHandler: @escaping (MEOutgoingMessageEncodingStatus) -> Void
    ) {
        completionHandler(
            MEOutgoingMessageEncodingStatus(
                canSign: true,
                canEncrypt: false,
                securityError: nil,
                addressesFailingEncryption: []
            )
        )
    }

    func encode(
        _ message: MEMessage,
        composeContext: MEComposeContext,
        completionHandler: @escaping (MEMessageEncodingResult) -> Void
    ) {
        // Auto-saves are told by the message's state, not its headers (D3).
        let raw = message.rawData
        let isAutoSave = message.state == .draft
        let contextID = composeContext.contextID
        Task {
            let result = await sender.encode(raw, isAutoSave: isAutoSave, contextID: contextID)
            completionHandler(Self.encodingResult(result))
        }
    }

    private static func encodingResult(_ result: SendResult) -> MEMessageEncodingResult {
        switch result {
        case .unchanged:
            return MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil)
        case .rewritten(let data):
            let message = MEEncodedOutgoingMessage(rawData: data, isSigned: false, isEncrypted: false)
            return MEMessageEncodingResult(encodedMessage: message, signingError: nil, encryptionError: nil)
        case .failed(let text):
            let error = NSError(
                domain: "lv.warp.nextcloudapplemail", code: 1, userInfo: [NSLocalizedDescriptionKey: text])
            return MEMessageEncodingResult(encodedMessage: nil, signingError: error, encryptionError: nil)
        }
    }

    // MARK: - Decoding

    func decodedMessage(forMessageData data: Data) -> MEDecodedMessage? {
        nil
    }

    func extensionViewController(signers messageSigners: [MEMessageSigner]) -> MEExtensionViewController? {
        nil
    }

    func extensionViewController(messageContext context: Data) -> MEExtensionViewController? {
        nil
    }

    func primaryActionClicked(
        forMessageContext context: Data,
        completionHandler: @escaping (MEExtensionViewController?) -> Void
    ) {
        completionHandler(nil)
    }
}
