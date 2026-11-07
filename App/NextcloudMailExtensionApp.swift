import SwiftUI

/// Starts the host app, or with a command-line option runs that command and exits (see `AppCommand`).
@main
enum Launcher {
    static func main() {
        if let command = AppCommand(arguments: CommandLine.arguments) {
            command.runAndExit()
        }
        // The app's one window has no tabs and doesn't go full screen, so AppKit adds neither "Show Tab Bar" and
        // "Show All Tabs" nor "Enter Full Screen" to the View menu.
        MainActor.assumeIsolated { NSWindow.allowsAutomaticWindowTabbing = false }
        UserDefaults.standard.register(defaults: ["NSFullScreenMenuItemEverywhere": false])
        NextcloudMailExtensionApp.main()
    }
}

struct NextcloudMailExtensionApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            SettingsView(model: model)
                .windowFullScreenBehavior(.disabled)
        }
        .windowResizability(.contentMinSize)
        .commands {
            // With nothing else in it, this leaves no View menu.
            CommandGroup(replacing: .toolbar) {}
            CommandGroup(replacing: .sidebar) {}
        }
    }
}
