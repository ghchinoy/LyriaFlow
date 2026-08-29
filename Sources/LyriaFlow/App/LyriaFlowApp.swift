import SwiftUI
import AppKit
import LyriaFlowKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows {
                window.makeKeyAndOrderFront(nil)
            }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}

@main
struct LyriaFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var coordinator = PlaybackCoordinator()

    var body: some Scene {
        WindowGroup("LyriaFlow") {
            MainSplitView(coordinator: coordinator)
                .preferredColorScheme(.dark)
                .frame(minWidth: 850, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
        }

        #if os(macOS)
        Settings {
            SettingsView(settings: coordinator.settings, coordinator: coordinator)
                .preferredColorScheme(.dark)
        }
        #endif
    }
}
