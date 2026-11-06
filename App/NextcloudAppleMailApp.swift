import SwiftUI

/// Starts the host app, or with a command-line option runs that command and exits (see `AppCommand`).
@main
enum Launcher {
    static func main() {
        if let command = AppCommand(arguments: CommandLine.arguments) {
            command.runAndExit()
        }
        NextcloudAppleMailApp.main()
    }
}

struct NextcloudAppleMailApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
