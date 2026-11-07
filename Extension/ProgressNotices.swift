import Foundation
import UserNotifications

/// Shows a notification while a slow upload runs, and when it ends, since Mail shows nothing meanwhile (R3,
/// docs/MAIL.md). Uploads that finish within `delay` show none, so that small emails don't notify each time. One
/// notification per message is replaced as the upload goes on. It names no files, only how many and their size.
final class ProgressNotices: @unchecked Sendable {
    static let shared = ProgressNotices()
    static let delay: TimeInterval = 2

    private let center = UNUserNotificationCenter.current()
    private let queue = DispatchQueue(label: "lv.warp.nextcloudmailextension.progress")
    private var waiting: [String: DispatchWorkItem] = [:]
    private var shown = Set<String>()
    private var started: [String: Date] = [:]

    func report(_ messageID: String, _ progress: SendProgress) {
        queue.async { [self] in
            let identifier = "upload-\(messageID)"
            switch progress {
            case .uploading(let files, let bytes):
                started[messageID] = Date()
                let work = DispatchWorkItem { [self] in
                    shown.insert(messageID)
                    post(identifier, "Uploading \(Self.amount(files, bytes)) to Nextcloud…")
                }
                waiting[messageID] = work
                queue.asyncAfter(deadline: .now() + Self.delay, execute: work)
            case .uploaded(let files, let bytes):
                waiting.removeValue(forKey: messageID)?.cancel()
                if shown.remove(messageID) != nil {
                    let seconds = Int(Date().timeIntervalSince(started[messageID] ?? Date()).rounded())
                    post(
                        identifier, "Uploaded \(Self.amount(files, bytes)) in \(seconds) s. Mail is sending the email.")
                }
                started[messageID] = nil
            case .failed:
                waiting.removeValue(forKey: messageID)?.cancel()
                // Mail's alert says what went wrong.
                if shown.remove(messageID) != nil {
                    center.removeDeliveredNotifications(withIdentifiers: [identifier])
                }
                started[messageID] = nil
            }
        }
    }

    private func post(_ identifier: String, _ text: String) {
        center.getNotificationSettings { [center] settings in
            let send = {
                let content = UNMutableNotificationContent()
                content.title = "NextcloudMailExtension"
                content.body = text
                center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil))
            }
            if settings.authorizationStatus == .notDetermined {
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted {
                        send()
                    }
                }
            } else {
                send()
            }
        }
    }

    /// Such as "3 files (24 MB)".
    static func amount(_ files: Int, _ bytes: Int) -> String {
        "\(files) \(files == 1 ? "file" : "files") (\(LinkText.size(bytes)))"
    }
}
