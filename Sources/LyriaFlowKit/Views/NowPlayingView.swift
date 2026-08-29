import SwiftUI

public struct NowPlayingView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @State private var rotationAngle: Double = 0

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Error Alert Banner if any
                if let error = coordinator.errorMessage {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.primary)
                        Spacer()
                        Button(action: { coordinator.errorMessage = nil }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 11))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(10)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(8)
                    .padding(.horizontal, 20)
                }

                if let currentTrack = coordinator.currentTrack {
                    // Centerpiece Vinyl & Visualizer
                    VStack(spacing: 16) {
                        ZStack {
                            // Subtle ambient glow
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [Color.purple.opacity(0.35), Color.clear],
                                        center: .center,
                                        startRadius: 20,
                                        endRadius: 90
                                    )
                                )
                                .frame(width: 180, height: 180)

                            // Vinyl Record Disc
                            VinylRecordView(isPlaying: coordinator.audioEngine.isPlaying)
                                .frame(width: 140, height: 140)
                        }
                        .padding(.top, 10)

                        // Real-time audio waveform bars
                        WaveformVisualizerView(
                            powerLevels: coordinator.audioEngine.powerLevels,
                            isPlaying: coordinator.audioEngine.isPlaying
                        )

                        // Track Metadata & Prompt Banner
                        VStack(spacing: 8) {
                            HStack(spacing: 8) {
                                Text(cleanModelName(currentTrack.modelId))
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color.purple.opacity(0.2))
                                    .foregroundColor(.purple)
                                    .cornerRadius(6)

                                Text(formattedDate(currentTrack.createdAt))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)

                                Spacer()

                                Button(action: {
                                    coordinator.toggleFavorite(for: currentTrack)
                                }) {
                                    Image(systemName: currentTrack.isFavorite ? "heart.fill" : "heart")
                                        .foregroundColor(currentTrack.isFavorite ? .red : .secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help("Favorite Track")

                                Button(action: {
                                    coordinator.revealInFinder(currentTrack)
                                }) {
                                    Image(systemName: "folder")
                                        .foregroundColor(.secondary)
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .help("Reveal in Finder")
                            }
                            .frame(maxWidth: 620)

                            Text(currentTrack.prompt)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                                .frame(maxWidth: 620)
                        }
                    }
                    .padding(.horizontal, 20)

                    Divider()
                        .padding(.horizontal, 20)

                    // Gemini Suggestions Section
                    SuggestionCardsView(coordinator: coordinator)
                        .padding(.horizontal, 20)

                } else {
                    // Empty state
                    VStack(spacing: 16) {
                        Spacer(minLength: 40)

                        ZStack {
                            Circle()
                                .fill(Color.purple.opacity(0.1))
                                .frame(width: 120, height: 120)

                            Image(systemName: "waveform.and.person.filled")
                                .font(.system(size: 48))
                                .foregroundColor(.purple.opacity(0.7))
                        }

                        VStack(spacing: 6) {
                            Text("Welcome to LyriaFlow")
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)

                            Text("Enter a musical prompt below or choose an inspiration chip to generate your first track using Lyria AI.")
                                .font(.system(size: 13))
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 420)
                        }

                        Spacer(minLength: 40)
                    }
                    .padding(.horizontal, 20)
                }
            }
            .padding(.vertical, 16)
        }
    }

    private func cleanModelName(_ raw: String) -> String {
        switch raw {
        case "lyria-3-clip-preview": return "Lyria 3 Clip"
        case "lyria-3-pro-preview": return "Lyria 3 Pro"
        case "lyria-002": return "Lyria 2"
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

struct VinylRecordView: View {
    let isPlaying: Bool
    @State private var rotation: Double = 0
    @State private var timer: Timer?

    var body: some View {
        ZStack {
            // Vinyl outer ring
            Circle()
                .fill(
                    RadialGradient(
                        colors: [Color.black, Color(white: 0.15), Color.black],
                        center: .center,
                        startRadius: 10,
                        endRadius: 70
                    )
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.4), radius: 10, x: 0, y: 4)

            // Grooves
            ForEach(1..<5) { idx in
                Circle()
                    .stroke(Color.white.opacity(0.04), lineWidth: 1)
                    .frame(width: CGFloat(idx * 24), height: CGFloat(idx * 24))
            }

            // Center Label
            Circle()
                .fill(
                    LinearGradient(
                        colors: [.purple, .indigo],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 48, height: 48)

            // Center Spindle Hole
            Circle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .frame(width: 12, height: 12)
        }
        .rotationEffect(.degrees(rotation))
        .onAppear {
            setupRotation()
        }
        .onChange(of: isPlaying) { _, playing in
            if playing {
                setupRotation()
            }
        }
    }

    private func setupRotation() {
        Timer.scheduledTimer(withTimeInterval: 0.03, repeats: true) { t in
            if isPlaying {
                rotation = (rotation + 1.2).truncatingRemainder(dividingBy: 360)
            }
        }
    }
}
