import Foundation
import Network

/// Whether the Mac has a network at all. macOS reports a request that Local Network privacy blocks as "not connected
/// to the internet", like a Mac without a network, so this tells the two apart (T21, docs/MAIL.md).
enum NetworkStatus {
    static func hasNetwork() async -> Bool {
        let monitor = NWPathMonitor()
        let answer = Once()
        let satisfied = await withCheckedContinuation { continuation in
            monitor.pathUpdateHandler = { path in
                if answer.first() {
                    continuation.resume(returning: path.status == .satisfied)
                }
            }
            monitor.start(queue: DispatchQueue(label: "lv.warp.nextcloudmailextension.network"))
        }
        monitor.cancel()
        return satisfied
    }

    /// True the first time only, as the monitor can report more than one path.
    private final class Once: @unchecked Sendable {
        private let lock = NSLock()
        private var done = false

        func first() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            guard !done else {
                return false
            }
            done = true
            return true
        }
    }
}
