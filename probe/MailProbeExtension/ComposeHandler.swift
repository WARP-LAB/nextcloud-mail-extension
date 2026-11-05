import AppKit
import Foundation
import MailKit

/// Logs the compose lifecycle so it can be lined up with `encode` calls. It blocks a send only for a `block` marker.
final class ComposeHandler: NSObject, MEComposeSessionHandler {
    func mailComposeSessionDidBegin(_ session: MEComposeSession) {
        log("compose-begin", session)
    }

    func mailComposeSessionDidEnd(_ session: MEComposeSession) {
        log("compose-end", session)
    }

    func viewController(for session: MEComposeSession) -> MEExtensionViewController {
        log("compose-popover", session)
        let contextID = session.composeContext.contextID.uuidString
        return ComposePopover(summary: "MailProbe\nSession \(session.sessionID.uuidString)\nContext \(contextID)\n\nDrop files here, or type a test password below.", contextID: contextID)
    }

    func allowMessageSendForSession(_ session: MEComposeSession, completion: @escaping (Error?) -> Void) {
        log("compose-can-send", session)
        let directive = ProbeDirective(subject: session.mailMessage.subject)
        // Saved so the round 3 checks can see what text and files a send check gets.
        if directive != nil, let raw = session.mailMessage.rawData, raw.count <= maxDumpBytes {
            let name = "can-send-\(Int(Date().timeIntervalSince1970 * 1000)).eml"
            ProbeLog.dump(raw, named: name)
            ProbeLog.event("compose-can-send-dumped", ["sessionID": session.sessionID.uuidString, "file": name])
        }
        if directive?.blocksSend == true {
            completion(MEComposeSessionError(.invalidBody, userInfo: [NSLocalizedDescriptionKey: "MailProbe test: the compose handler blocked this send."]))
            return
        }
        completion(nil)
    }

    func additionalHeaders(for session: MEComposeSession) -> [String: [String]] {
        log("compose-additional-headers", session)
        return [:]
    }

    private func log(_ event: String, _ session: MEComposeSession) {
        var fields = contextFields(session.mailMessage, session.composeContext)
        fields["sessionID"] = session.sessionID.uuidString
        fields["marker"] = ProbeDirective(subject: session.mailMessage.subject)?.text
        ProbeLog.event(event, fields)
    }
}

/// Files dropped on the popover, by compose context, so `encode` can find them at send.
final class PopoverFiles: @unchecked Sendable {
    static let shared = PopoverFiles()
    private let lock = NSLock()
    private var urlsByContext: [String: [URL]] = [:]

    func add(_ urls: [URL], to context: String) {
        lock.lock()
        defer { lock.unlock() }
        urlsByContext[context, default: []] += urls
    }

    func urls(for context: String) -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return urlsByContext[context] ?? []
    }
}

/// Passwords typed in the popover, by compose context. A reopened draft gets a new context but keeps its message ID,
/// so `encode` links each context to the message ID it sees. Only the length is ever logged.
final class PopoverPasswords: @unchecked Sendable {
    static let shared = PopoverPasswords()
    private let lock = NSLock()
    private var passwordsByContext: [String: String] = [:]
    private var messagesByContext: [String: String] = [:]

    func set(_ password: String, for context: String) {
        lock.lock()
        defer { lock.unlock() }
        passwordsByContext[context] = password.isEmpty ? nil : password
    }

    func link(context: String, toMessage message: String) {
        lock.lock()
        defer { lock.unlock() }
        messagesByContext[context] = message
    }

    func password(for context: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return passwordsByContext[context]
    }

    /// Looks in this context first, then in other contexts of the same message.
    func password(for context: String, message: String) -> (password: String, viaMessageID: Bool)? {
        lock.lock()
        defer { lock.unlock() }
        if let password = passwordsByContext[context] { return (password, false) }
        for (other, linked) in messagesByContext where linked == message {
            if let password = passwordsByContext[other] { return (password, true) }
        }
        return nil
    }
}

/// `readableBytes` is -1 if the sandbox no longer lets the extension read the file.
func popoverFileFields(_ urls: [URL]) -> [[String: Any]] {
    urls.map { ["name": $0.lastPathComponent, "readableBytes": (try? Data(contentsOf: $0, options: .alwaysMapped))?.count ?? -1] }
}

private final class DropView: NSView {
    var onDrop: (([URL]) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        onDrop?(urls)
        return !urls.isEmpty
    }
}

private final class ComposePopover: MEExtensionViewController, NSTextFieldDelegate {
    private let summary: String
    private let contextID: String

    init(summary: String, contextID: String) {
        self.summary = summary
        self.contextID = contextID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    override func loadView() {
        let container = DropView(frame: NSRect(x: 0, y: 0, width: 340, height: 230))
        let label = NSTextField(wrappingLabelWithString: summary)
        label.frame = NSRect(x: 16, y: 52, width: 308, height: 162)
        label.isSelectable = true
        label.unregisterDraggedTypes()
        container.addSubview(label)
        let passwordField = NSSecureTextField(frame: NSRect(x: 16, y: 16, width: 308, height: 24))
        passwordField.placeholderString = "Test password for this message"
        passwordField.stringValue = PopoverPasswords.shared.password(for: contextID) ?? ""
        passwordField.delegate = self
        container.addSubview(passwordField)
        container.onDrop = { [summary, contextID] urls in
            PopoverFiles.shared.add(urls, to: contextID)
            ProbeLog.event("popover-drop", ["contextID": contextID, "files": popoverFileFields(urls)])
            label.stringValue = "\(summary)\n\nDropped: \(urls.map(\.lastPathComponent).joined(separator: ", "))"
        }
        view = container
        preferredContentSize = container.frame.size
    }

    // Saved on every change, because the popover can close without the field ending its editing.
    func controlTextDidChange(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        PopoverPasswords.shared.set(field.stringValue, for: contextID)
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField else { return }
        ProbeLog.event("popover-password", ["contextID": contextID, "characters": field.stringValue.count])
    }
}
