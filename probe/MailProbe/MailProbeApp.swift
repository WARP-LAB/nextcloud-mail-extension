import SwiftUI

@main
struct MailProbeApp: App {
    var body: some Scene {
        WindowGroup {
            VStack(alignment: .leading, spacing: 8) {
                Text("MailProbe").font(.title2)
                Text("In Mail, open Settings > Extensions, enable MailProbe and choose it for message security.")
                Text("Only messages with a [probe ...] marker in the subject are changed.")
            }
            .padding(24)
            .frame(width: 420)
        }
    }
}
