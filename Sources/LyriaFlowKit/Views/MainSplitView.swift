import SwiftUI

public struct MainSplitView: View {
    @ObservedObject public var coordinator: PlaybackCoordinator
    @State private var showingSettings: Bool = false

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        NavigationSplitView {
            HistorySidebarView(coordinator: coordinator, showingSettings: $showingSettings)
        } detail: {
            VStack(spacing: 0) {
                // Prompt Bar at the top
                PromptInputBar(coordinator: coordinator)

                Divider()

                // Center Stage Canvas
                NowPlayingView(coordinator: coordinator)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom Transport Player
                TransportBar(coordinator: coordinator)
            }
        }
        .frame(minWidth: 850, minHeight: 600)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: coordinator.settings, coordinator: coordinator)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
        .task {
            // Asynchronously connect without blocking initial window display
            Task {
                await coordinator.connectAndVerifyServer()
            }
        }
    }
}
