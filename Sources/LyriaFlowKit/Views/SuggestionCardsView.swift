import SwiftUI

public struct SuggestionCardsView: View {
    @ObservedObject var coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Gemini Next-Track Suggestions", systemImage: "sparkles")
                    .font(.headline)
                    .foregroundColor(.primary)

                Spacer()

                if coordinator.isLoadingSuggestions {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Asking Gemini...")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else if coordinator.currentSuggestions != nil {
                    Text("Select a prompt or let Auto-Play choose")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if coordinator.isLoadingSuggestions {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                            .frame(height: 110)
                            .overlay(
                                ProgressView()
                                    .scaleEffect(0.8)
                            )
                    }
                }
            } else if let suggestions = coordinator.currentSuggestions {
                HStack(spacing: 12) {
                    SuggestionCard(
                        type: .similar,
                        prompt: suggestions.similar,
                        accentColor: .cyan,
                        isPreGenerating: coordinator.pregeneratingPrompt == suggestions.similar && coordinator.pregeneratedTrack == nil,
                        isPreGeneratedReady: coordinator.pregeneratedTrack?.prompt == suggestions.similar,
                        onPlayNow: { coordinator.selectSuggestion(.similar, playImmediately: true) },
                        onQueue: { coordinator.selectSuggestion(.similar, playImmediately: false) }
                    )

                    SuggestionCard(
                        type: .fun,
                        prompt: suggestions.fun,
                        accentColor: .orange,
                        isPreGenerating: coordinator.pregeneratingPrompt == suggestions.fun && coordinator.pregeneratedTrack == nil,
                        isPreGeneratedReady: coordinator.pregeneratedTrack?.prompt == suggestions.fun,
                        onPlayNow: { coordinator.selectSuggestion(.fun, playImmediately: true) },
                        onQueue: { coordinator.selectSuggestion(.fun, playImmediately: false) }
                    )

                    SuggestionCard(
                        type: .wild,
                        prompt: suggestions.wild,
                        accentColor: .pink,
                        isPreGenerating: coordinator.pregeneratingPrompt == suggestions.wild && coordinator.pregeneratedTrack == nil,
                        isPreGeneratedReady: coordinator.pregeneratedTrack?.prompt == suggestions.wild,
                        onPlayNow: { coordinator.selectSuggestion(.wild, playImmediately: true) },
                        onQueue: { coordinator.selectSuggestion(.wild, playImmediately: false) }
                    )
                }
            } else {
                Text("Generate or play a track to see AI suggestions for what to play next.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 24)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.3))
                    )
            }
        }
    }
}

struct SuggestionCard: View {
    let type: SuggestionType
    let prompt: String
    let accentColor: Color
    let isPreGenerating: Bool
    let isPreGeneratedReady: Bool
    let onPlayNow: () -> Void
    let onQueue: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: type.iconName)
                    .foregroundColor(accentColor)
                    .font(.system(size: 13, weight: .bold))

                Text(type.rawValue)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)

                Spacer()

                if isPreGeneratedReady {
                    HStack(spacing: 3) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Queued")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15))
                    .cornerRadius(6)
                } else if isPreGenerating {
                    HStack(spacing: 3) {
                        ProgressView()
                            .scaleEffect(0.5)
                        Text("Pre-caching")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15))
                    .cornerRadius(6)
                }
            }

            Text(prompt)
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .topLeading)

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                Button(action: onPlayNow) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Play")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor.opacity(0.8))
                .controlSize(.small)

                Button(action: onQueue) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.badge.plus")
                        Text("Queue")
                    }
                    .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 125, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovered ? 0.8 : 0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    isPreGeneratedReady ? Color.green.opacity(0.6) : (isHovered ? accentColor.opacity(0.5) : Color.white.opacity(0.08)),
                    lineWidth: isPreGeneratedReady || isHovered ? 1.5 : 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
