import SwiftUI

public struct TransportBar: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @ObservedObject var audioEngine: AudioEngine
    @ObservedObject var settings: AppSettings

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
        self.audioEngine = coordinator.audioEngine
        self.settings = coordinator.settings
    }

    public var body: some View {
        VStack(spacing: 6) {
            // Scrubber Row
            HStack(spacing: 8) {
                Text(formatTime(audioEngine.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .trailing)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        // Background track
                        Capsule()
                            .fill(Color.secondary.opacity(0.2))
                            .frame(height: 4)

                        // Progress fill
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [.purple, .cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: audioEngine.duration > 0
                                    ? max(0, min(geo.size.width, geo.size.width * CGFloat(audioEngine.currentTime / audioEngine.duration)))
                                    : 0,
                                height: 4
                            )
                    }
                    .frame(height: 14)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard audioEngine.duration > 0 else { return }
                                let fraction = max(0, min(1, value.location.x / geo.size.width))
                                audioEngine.seek(to: audioEngine.duration * Double(fraction))
                            }
                    )
                }
                .frame(height: 14)

                Text(formatTime(audioEngine.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 40, alignment: .leading)
            }

            // Controls Row
            HStack(spacing: 16) {
                // Left status / Up Next Queue Status Pill
                HStack(spacing: 6) {
                    if let first = coordinator.queue.first {
                        switch first.status {
                        case .ready:
                            Image(systemName: "bolt.fill")
                                .foregroundColor(.green)
                                .font(.system(size: 10))
                            Text("Next: Ready")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.green)
                        case .generating:
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                            Text("Pre-generating next...")
                                .font(.system(size: 11))
                                .foregroundColor(.orange)
                        case .queued:
                            Image(systemName: "list.bullet")
                                .foregroundColor(.purple)
                                .font(.system(size: 10))
                            Text("Queue: \(coordinator.queue.count) track\(coordinator.queue.count == 1 ? "" : "s")")
                                .font(.system(size: 11))
                                .foregroundColor(.purple)
                        case .failed:
                            Image(systemName: "exclamationmark.circle")
                                .foregroundColor(.red)
                                .font(.system(size: 10))
                            Text("Queue item failed")
                                .font(.system(size: 11))
                                .foregroundColor(.red)
                        }

                        Text("— \(first.prompt)")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else if coordinator.isGenerating {
                        ProgressView()
                            .scaleEffect(0.5)
                            .frame(width: 12, height: 12)
                        Text(coordinator.generationMessage)
                            .font(.system(size: 11))
                            .foregroundColor(.purple)
                            .lineLimit(1)
                    } else if settings.autoPlayEnabled {
                        Image(systemName: "infinity")
                            .foregroundColor(.purple)
                            .font(.system(size: 10))
                        Text("Auto-Play ready")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    } else {
                        Text(coordinator.currentTrack != nil ? "Ready" : "LyriaFlow Idle")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(width: 250, alignment: .leading)

                Spacer()

                // Center Playback Buttons
                HStack(spacing: 14) {
                    // Loop Button
                    Button(action: {
                        settings.loopEnabled.toggle()
                        audioEngine.isLooping = settings.loopEnabled
                    }) {
                        Image(systemName: settings.loopEnabled ? "repeat.1" : "repeat")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(settings.loopEnabled ? .purple : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Loop Track")

                    // Play/Pause Main Button
                    Button(action: {
                        audioEngine.togglePlayPause()
                    }) {
                        ZStack {
                            Circle()
                                .fill(LinearGradient(colors: [.purple, .cyan], startPoint: .topLeading, endPoint: .bottomTrailing))
                                .frame(width: 38, height: 38)
                                .shadow(color: Color.purple.opacity(0.35), radius: 6, x: 0, y: 2)

                            Image(systemName: audioEngine.isPlaying ? "pause.fill" : "play.fill")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundColor(.white)
                                .offset(x: audioEngine.isPlaying ? 0 : 1)
                        }
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.space, modifiers: [])
                    .disabled(audioEngine.currentURL == nil && !coordinator.isGenerating)

                    // Skip / Next Button
                    Button(action: {
                        if !coordinator.queue.isEmpty {
                            coordinator.playQueueItemNow(id: coordinator.queue[0].id)
                        } else if let suggestions = coordinator.currentSuggestions {
                            let prompt = [suggestions.similar, suggestions.fun, suggestions.wild].randomElement() ?? suggestions.similar
                            Task {
                                await coordinator.generateAndPlay(prompt: prompt)
                            }
                        }
                    }) {
                        Image(systemName: "forward.end.fill")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                    }
                    .buttonStyle(.plain)
                    .help("Skip / Play Next")
                }

                Spacer()

                // Right Controls (Auto-Play Toggle & Volume)
                HStack(spacing: 14) {
                    // Auto-Play Toggle
                    Toggle(isOn: Binding(
                        get: { settings.autoPlayEnabled },
                        set: { enabled in
                            settings.autoPlayEnabled = enabled
                            if enabled && coordinator.queue.isEmpty, let suggestions = coordinator.currentSuggestions {
                                coordinator.scheduleAutoPlaySuggestion(suggestions: suggestions)
                            }
                        }
                    )) {
                        HStack(spacing: 4) {
                            Image(systemName: "infinity")
                                .font(.system(size: 11, weight: .bold))
                            Text("Auto-Play")
                                .font(.system(size: 11, weight: .medium))
                        }
                        .foregroundColor(settings.autoPlayEnabled ? .purple : .secondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .help("Auto-generate and queue next tracks in background")

                    // Volume Slider
                    HStack(spacing: 6) {
                        Image(systemName: volumeIcon)
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                            .frame(width: 14)

                        Slider(
                            value: Binding(
                                get: { settings.volume },
                                set: {
                                    settings.volume = $0
                                    audioEngine.volume = Float($0)
                                }
                            ),
                            in: 0...1
                        )
                        .frame(width: 75)
                        .controlSize(.mini)
                    }
                }
                .frame(width: 230, alignment: .trailing)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            Color(nsColor: .windowBackgroundColor)
                .overlay(
                    Rectangle()
                        .frame(height: 1)
                        .foregroundColor(Color.white.opacity(0.08)),
                    alignment: .top
                )
        )
    }

    private var volumeIcon: String {
        if settings.volume <= 0.001 { return "speaker.slash.fill" }
        if settings.volume < 0.33 { return "speaker.wave.1.fill" }
        if settings.volume < 0.66 { return "speaker.wave.2.fill" }
        return "speaker.wave.3.fill"
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard !seconds.isNaN && seconds >= 0 else { return "0:00" }
        let s = Int(seconds)
        let mins = s / 60
        let secs = s % 60
        return String(format: "%d:%02d", mins, secs)
    }
}
