import SwiftUI

/// Starts the host app, or with a command-line option runs that command and exits (see `AppCommand`).
@main
enum Launcher {
    static func main() {
        if let command = AppCommand(arguments: CommandLine.arguments) {
            command.runAndExit()
        }
        // The app's one window has no tabs, so this takes "Show Tab Bar" and "Show All Tabs" out of the View menu.
        // "Enter Full Screen" stays: SwiftUI keeps the View menu even when it's empty.
        MainActor.assumeIsolated { NSWindow.allowsAutomaticWindowTabbing = false }
        NextcloudMailExtensionApp.main()
    }
}

struct NextcloudMailExtensionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SettingsView(model: model)
        }
        .windowResizability(.contentMinSize)
    }
}
