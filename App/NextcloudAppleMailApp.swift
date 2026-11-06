import SwiftUI

/// Starts the host app. With `--check-storage`, it runs the storage check from the command line instead, prints the
/// result as JSON and exits with 0 if it passed.
@main
enum Launcher {
    static func main() {
        if CommandLine.arguments.contains("--check-storage") {
            exit(StorageCheckReport.run() ? 0 : 1)
        }
        NextcloudAppleMailApp.main()
    }
}

struct NextcloudAppleMailApp: App {
    var body: some Scene {
        WindowGroup {
            SetupView()
        }
    }
}

/// Runs the storage check and reports it, for the command line and for the window.
enum StorageCheckReport {
    /// Writes a fresh value to every kind of shared storage, so the extension can read it back.
    static func check() -> (identifier: String?, result: StorageCheck.Result?) {
        guard let identifier = SharedStorage.appGroupIdentifier else {
            return (nil, nil)
        }
        let value = "written by the host app at \(ISO8601DateFormatter().string(from: Date()))"
        return (identifier, StorageCheck(groupIdentifier: identifier).write(value))
    }

    static func run() -> Bool {
        let (identifier, result) = check()
        guard let identifier, let result else {
            FileHandle.standardError.write(Data("error: no App Group identifier in Info.plist\n".utf8))
            return false
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = (try? encoder.encode(result)).flatMap { String(bytes: $0, encoding: .utf8) } ?? "{}"
        print("App Group: \(identifier)\n\(json)\npassed: \(result.passed)")
        return result.passed
    }
}

struct SetupView: View {
    @State private var report = "Not run yet."

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("NextcloudAppleMail").font(.title2)
            Text("Settings and the Nextcloud login arrive in task T2.")
            Button("Run the storage check") {
                let (identifier, result) = StorageCheckReport.check()
                if let identifier, let result {
                    report = """
                        App Group: \(identifier)
                        Container: \(result.container)
                        Settings: \(result.settings)
                        Keychain: \(result.keychain)
                        """
                } else {
                    report = "No App Group identifier in Info.plist."
                }
            }
            Text(report).font(.system(.body, design: .monospaced)).textSelection(.enabled)
        }
        .padding(24)
        .frame(width: 520, alignment: .leading)
    }
}
