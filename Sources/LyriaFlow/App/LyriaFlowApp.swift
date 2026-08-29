import SwiftUI
import LyriaFlowKit

@main
struct LyriaFlowApp: App {
    var body: some Scene {
        WindowGroup {
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
