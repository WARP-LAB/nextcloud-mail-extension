import MailKit

/// Reports that the extension can sign but not encrypt, so Mail offers the Sign button, which is the upload switch
/// (docs/MAIL.md). Until the send flow arrives in task T5, `encode` returns nil, so Mail sends every message unchanged.
final class SecurityHandler: NSObject, MEMessageSecurityHandler {
    static let shared = SecurityHandler()

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
        completionHandler(MEMessageEncodingResult(encodedMessage: nil, signingError: nil, encryptionError: nil))
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
