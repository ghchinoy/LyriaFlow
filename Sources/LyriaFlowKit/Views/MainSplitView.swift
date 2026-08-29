import SwiftUI
import AppKit

public struct MainSplitView: View {
    @ObservedObject public var coordinator: PlaybackCoordinator
    @State private var showingSettings: Bool = false
    @State private var eventMonitor: Any? = nil

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
        .sheet(item: $coordinator.inspectingTrack) { track in
            TrackInspectorView(track: track, coordinator: coordinator)
        }
        .onAppear {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            setupKeyboardMonitor()
        }
        .onDisappear {
            if let monitor = eventMonitor {
                NSEvent.removeMonitor(monitor)
                eventMonitor = nil
            }
        }
        .task {
            // Asynchronously connect without blocking initial window display
            Task {
                await coordinator.connectAndVerifyServer()
            }
        }
    }

    private func setupKeyboardMonitor() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Spacebar is key code 49
            if event.keyCode == 49 {
                // If modifier keys like Command, Control, Option are held (e.g. Cmd+Space), do not intercept
                let modifiers = event.modifierFlags.intersection([.command, .control, .option])
                guard modifiers.isEmpty else { return event }

                // If a text editing view has first responder, let it handle space character
                let targetWindow = event.window ?? NSApp.keyWindow
                if let firstResponder = targetWindow?.firstResponder {
                    if firstResponder is NSTextView || firstResponder is NSTextField || firstResponder is NSTextInputClient {
                        return event
                    }
                }
                // Toggle playback if ready
                if coordinator.audioEngine.currentURL != nil || coordinator.currentTrack != nil {
                    coordinator.audioEngine.togglePlayPause()
                    return nil
                }
            }
            return event
        }
    }
}
