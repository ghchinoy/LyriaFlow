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
                    Text("Select a prompt to queue or let Auto-Play choose")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if coordinator.isLoadingSuggestions {
                HStack(spacing: 12) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .windowBackgroundColor).opacity(0.6))
                            .frame(height: 125)
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
                        queueIndex: coordinator.queue.firstIndex(where: { $0.prompt == suggestions.similar }),
                        queueStatus: coordinator.queue.first(where: { $0.prompt == suggestions.similar })?.status,
                        onPlayNow: {
                            Task {
                                await coordinator.generateAndPlay(prompt: suggestions.similar)
                            }
                        },
                        onQueue: {
                            coordinator.addToQueue(
                                prompt: suggestions.similar,
                                origin: SuggestionType.similar.rawValue
                            )
                        }
                    )

                    SuggestionCard(
                        type: .fun,
                        prompt: suggestions.fun,
                        accentColor: .orange,
                        queueIndex: coordinator.queue.firstIndex(where: { $0.prompt == suggestions.fun }),
                        queueStatus: coordinator.queue.first(where: { $0.prompt == suggestions.fun })?.status,
                        onPlayNow: {
                            Task {
                                await coordinator.generateAndPlay(prompt: suggestions.fun)
                            }
                        },
                        onQueue: {
                            coordinator.addToQueue(
                                prompt: suggestions.fun,
                                origin: SuggestionType.fun.rawValue
                            )
                        }
                    )

                    SuggestionCard(
                        type: .wild,
                        prompt: suggestions.wild,
                        accentColor: .pink,
                        queueIndex: coordinator.queue.firstIndex(where: { $0.prompt == suggestions.wild }),
                        queueStatus: coordinator.queue.first(where: { $0.prompt == suggestions.wild })?.status,
                        onPlayNow: {
                            Task {
                                await coordinator.generateAndPlay(prompt: suggestions.wild)
                            }
                        },
                        onQueue: {
                            coordinator.addToQueue(
                                prompt: suggestions.wild,
                                origin: SuggestionType.wild.rawValue
                            )
                        }
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
    let queueIndex: Int?
    let queueStatus: QueueItemStatus?
    let onPlayNow: () -> Void
    let onQueue: () -> Void

    @State private var isHovered: Bool = false

    var isQueued: Bool { queueIndex != nil }

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

                if let idx = queueIndex {
                    if let status = queueStatus, case .ready = status {
                        HStack(spacing: 3) {
                            Image(systemName: "bolt.fill")
                            Text("Ready #\(idx + 1)")
                        }
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.green)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.green.opacity(0.15))
                        .cornerRadius(6)
                    } else if let status = queueStatus, case .generating = status {
                        HStack(spacing: 3) {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 8, height: 8)
                            Text("Generating #\(idx + 1)")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.15))
                        .cornerRadius(6)
                    } else {
                        HStack(spacing: 3) {
                            Image(systemName: "list.number")
                            Text("Queued #\(idx + 1)")
                        }
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.purple)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.purple.opacity(0.15))
                        .cornerRadius(6)
                    }
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
                        Text("Play Now")
                    }
                    .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(accentColor.opacity(0.85))
                .controlSize(.small)

                Button(action: onQueue) {
                    HStack(spacing: 4) {
                        Image(systemName: isQueued ? "checkmark" : "plus")
                        Text(isQueued ? "Add Again" : "Queue")
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
                    isQueued ? Color.purple.opacity(0.6) : (isHovered ? accentColor.opacity(0.5) : Color.white.opacity(0.08)),
                    lineWidth: isQueued || isHovered ? 1.5 : 1
                )
        )
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }
}
