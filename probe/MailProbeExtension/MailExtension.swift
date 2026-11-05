import MailKit

final class MailExtension: NSObject, MEExtension {
    func handler(for session: MEComposeSession) -> MEComposeSessionHandler {
        ComposeHandler()
    }

    func handlerForMessageSecurity() -> MEMessageSecurityHandler {
        SecurityHandler.shared
    }
}
