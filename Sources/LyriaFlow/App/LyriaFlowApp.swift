import SwiftUI
import AppKit
import LyriaFlowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct LyriaFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup("LyriaFlow") {
            MainSplitView()
                .preferredColorScheme(.dark)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            CommandGroup(replacing: .newItem) {
                // Custom quick actions
            }
        }

        #if os(macOS)
        Settings {
            SettingsView(settings: AppSettings.shared, coordinator: PlaybackCoordinator(settings: AppSettings.shared))
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
