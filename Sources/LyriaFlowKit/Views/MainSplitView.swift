import SwiftUI

public struct MainSplitView: View {
    @StateObject private var coordinator = PlaybackCoordinator()
    @State private var showingSettings: Bool = false

    public init() {}

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
        .frame(minWidth: 800, minHeight: 560)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: coordinator.settings, coordinator: coordinator)
        }
        .task {
            await coordinator.connectAndVerifyServer()
        }
    }
}
