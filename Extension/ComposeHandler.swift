import AppKit
import MailKit

/// Until the password popover arrives in task T6, the toolbar popover shows what the extension can read of the
/// values the host app wrote with its storage check (task T1, docs/RISKS.md R17).
final class ComposeHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {}

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {}

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        StorageCheckPopover()
    }
}

private final class StorageCheckPopover: MEExtensionViewController {
    override func loadView() {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let label = NSTextField(wrappingLabelWithString: Self.report())
        label.frame = container.bounds.insetBy(dx: 16, dy: 16)
        label.isSelectable = true
        container.addSubview(label)
        view = container
        preferredContentSize = container.frame.size
    }

    private static func report() -> String {
        guard let identifier = SharedStorage.appGroupIdentifier else {
            return "No App Group identifier in Info.plist."
        }
        let result = StorageCheck(groupIdentifier: identifier).read()
        return """
            Read by the extension:
            App Group: \(identifier)
            Container: \(result.container)
            Settings: \(result.settings)
            Keychain: \(result.keychain)
            """
    }
}
