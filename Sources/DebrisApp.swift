import AppKit
import SwiftUI

/// Window state restoration is off: Debris has nothing worth restoring, and a previous instance
/// that died mid-write leaves state behind that stalls the next launch before any window opens.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: ["ApplePersistenceIgnoreState": true])
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.windows.forEach { $0.isRestorable = false }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

@main
struct DebrisApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(model)
                .frame(minWidth: 900, minHeight: 560)
                .task { await model.start() }
        }
        .defaultSize(width: 1120, height: 720)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
