import AppKit
import SwiftUI

/// The debug-only command-line options that the Mail checks use (docs/TESTING.md, "Driving Mail from the command
/// line").
enum DebugCommands {
    /// Prints the settings as JSON, after merging in the settings in `json`, such as `{"sharing":"eachFile"}`.
    static func settings(_ json: String?) -> Bool {
        guard let group = SharedStorage.appGroupIdentifier, let store = SettingsStore(groupIdentifier: group) else {
            return fail("no App Group identifier in Info.plist")
        }
        var settings = store.load()
        do {
            if let json {
                var values = try object(JSONEncoder().encode(settings))
                for (key, value) in try object(Data(json.utf8)) {
                    values[key] = value
                }
                settings = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: values))
                store.save(settings)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            print(String(bytes: try encoder.encode(settings), encoding: .utf8) ?? "{}")
            return true
        } catch {
            return fail("the settings couldn't be read or changed: \(error.localizedDescription)")
        }
    }

    static func debugDumps(_ action: String) -> Bool {
        guard let group = SharedStorage.appGroupIdentifier else {
            return fail("no App Group identifier in Info.plist")
        }
        switch action {
        case "on", "off":
            DebugDumps.turn(on: action == "on", group: group)
            print("Debug dumps are \(action).")
        case "take":
            for dump in DebugDumps.take(group: group) {
                print("\(dump.name)\t\(dump.data.base64EncodedString())")
            }
        default:
            return fail("use --debug-dumps on, off or take")
        }
        return true
    }

    /// Draws the settings window off screen and prints it as a PNG in base64, so that its layout can be checked
    /// without a screen or Screen Recording.
    @MainActor
    static func renderWindow() -> Bool {
        _ = NSApplication.shared
        let view = NSHostingView(rootView: SettingsView(model: AppModel()))
        view.frame = NSRect(x: 0, y: 0, width: 640, height: 2000)
        let window = NSWindow(contentRect: view.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = view
        // Lets onAppear run and the form lay itself out.
        RunLoop.main.run(until: Date().addingTimeInterval(1))
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return fail("the window couldn't be drawn")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            return fail("the window couldn't be drawn")
        }
        print(png.base64EncodedString())
        return true
    }

    private static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CocoaError(.coderReadCorrupt)
        }
        return object
    }

    private static func fail(_ text: String) -> Bool {
        FileHandle.standardError.write(Data("error: \(text)\n".utf8))
        return false
    }
}
