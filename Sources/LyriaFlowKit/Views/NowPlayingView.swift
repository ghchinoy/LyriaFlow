import SwiftUI

public struct NowPlayingView: View {
    @ObservedObject var coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // Error Alert Banner if any
                if let error = coordinator.errorMessage {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                            .font(.subheadline)
                        Text(error)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: { coordinator.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.orange.opacity(0.35), lineWidth: 1)
                    )
                    .padding(.horizontal, 24)
                }

                if let currentTrack = coordinator.currentTrack {
                    // Centerpiece 32-Bar Audio-Reactive Spectrum Visualizer
                    VStack(spacing: 20) {
                        WaveformVisualizerView(
                            powerLevels: coordinator.audioEngine.powerLevels,
                            isPlaying: coordinator.audioEngine.isPlaying
                        )

                        // Track Metadata & Prompt Banner
                        VStack(spacing: 10) {
                            HStack(spacing: 8) {
                                Text(cleanModelName(currentTrack.modelId))
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.18))
                                    .foregroundColor(.purple)
                                    .clipShape(Capsule())

                                Text(formattedDate(currentTrack.createdAt))
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button(action: {
                                    coordinator.inspectingTrack = currentTrack
                                }) {
                                    Image(systemName: "info.circle")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                                .help("Get Info / Track Metadata")
                                .accessibilityLabel("Inspect track metadata")

                                Button(action: {
                                    coordinator.toggleFavorite(for: currentTrack)
                                }) {
                                    Image(systemName: currentTrack.isFavorite ? "heart.fill" : "heart")
                                        .foregroundColor(currentTrack.isFavorite ? .red : .secondary)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                                .help("Favorite Track")
                                .accessibilityLabel(currentTrack.isFavorite ? "Unfavorite track" : "Favorite track")

                                Button(action: {
                                    coordinator.revealInFinder(currentTrack)
                                }) {
                                    Image(systemName: "folder")
                                        .foregroundColor(.secondary)
                                        .font(.subheadline)
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                                .accessibilityLabel("Reveal in Finder")
                            }
                            .frame(maxWidth: 620)

                            Text(currentTrack.prompt)
                                .font(.title2.weight(.semibold))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .textSelection(.enabled)
                                .lineLimit(3)
                                .frame(maxWidth: 620)
                        }
                        .contentShape(Rectangle())
                        .contextMenu {
                            Button("Get Info") { coordinator.inspectingTrack = currentTrack }
                            Button(currentTrack.isFavorite ? "Unfavorite" : "Favorite") { coordinator.toggleFavorite(for: currentTrack) }
                            Button("Copy Prompt") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(currentTrack.prompt, forType: .string)
                            }
                            Button("Reveal in Finder") { coordinator.revealInFinder(currentTrack) }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)

                    Divider()
                        .padding(.horizontal, 24)

                    // Gemini Suggestions Section
                    SuggestionCardsView(coordinator: coordinator)
                        .padding(.horizontal, 24)
                } else {
                    // Empty state
                    VStack(spacing: 20) {
                        Spacer(minLength: 50)

                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.12))
                                .frame(width: 110, height: 110)

                            Image(systemName: "music.note.waveform")
                                .font(.system(size: 46))
                                .foregroundColor(.purple.opacity(0.85))
                        }

                        VStack(spacing: 8) {
                            Text("Welcome to LyriaFlow")
                                .font(.title2.weight(.bold))
                                .foregroundColor(.primary)

                            Text("Enter a musical prompt below or choose an inspiration chip to generate your first track using Lyria AI.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 440)
                        }

                        Spacer(minLength: 50)
                    }
                    .padding(.horizontal, 24)
                }
            }
            .padding(.vertical, 20)
        }
    }

    private func cleanModelName(_ raw: String) -> String {
        switch raw {
        case "lyria-3-clip-preview": return "Lyria 3 Clip"
        case "lyria-3-pro-preview": return "Lyria 3 Pro"
        default: return raw
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
