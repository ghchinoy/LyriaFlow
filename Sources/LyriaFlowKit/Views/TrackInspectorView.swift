import SwiftUI
import AppKit

public struct TrackInspectorView: View {
    public let track: Track
    @ObservedObject public var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    public init(track: Track, coordinator: PlaybackCoordinator) {
        self.track = track
        self.coordinator = coordinator
    }

    private var liveTrack: Track {
        coordinator.tracks.first(where: { $0.id == track.id })
            ?? (coordinator.currentTrack?.id == track.id ? coordinator.currentTrack! : track)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 10) {
                Image(systemName: "info.circle.fill")
                    .foregroundColor(.purple)
                    .font(.title3)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Track Inspector")
                        .font(.headline.weight(.bold))
                    Text("Technical metadata and generation parameters")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Done") {
                    if coordinator.inspectingTrack?.id == track.id {
                        coordinator.inspectingTrack = nil
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Section 1: Musical Prompt
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label("Musical Prompt", systemImage: "quote.opening")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.primary)

                            Spacer()

                            Button(action: {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(liveTrack.prompt, forType: .string)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "doc.on.doc")
                                    Text("Copy")
                                }
                                .font(.caption)
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.purple)
                            .help("Copy full prompt to clipboard")
                        }

                        Text(liveTrack.prompt)
                            .font(.body)
                            .foregroundColor(.primary)
                            .textSelection(.enabled)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.primary.opacity(0.04))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    }

                    // Section 2: Generation Technical Details
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Generation Specs", systemImage: "slider.horizontal.3")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)

                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                            GridRow {
                                Text("Lyria Model:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    Text(cleanModelName(liveTrack.modelId))
                                        .font(.caption.weight(.bold))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(Color.purple.opacity(0.18))
                                        .foregroundColor(.purple)
                                        .clipShape(Capsule())
                                    Text("(\(liveTrack.modelId))")
                                        .font(.caption.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }

                            GridRow {
                                Text("Duration:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(formatDuration(liveTrack.duration))
                                    .font(.caption.monospacedDigit())
                                    .foregroundColor(.primary)
                            }

                            GridRow {
                                Text("Format:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    let detected = AudioFormatDetector.detectFormat(for: coordinator.persistence.audioFileURL(for: liveTrack))
                                    Text(detected.displayName)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    if detected == .mp3 {
                                        Text("C2PA Signed")
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 1.5)
                                            .background(Color.green.opacity(0.18))
                                            .foregroundColor(.green)
                                            .clipShape(Capsule())
                                    }
                                }
                            }

                            GridRow {
                                Text("Seed:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 6) {
                                    if let seed = liveTrack.seed {
                                        Text("\(seed)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundColor(.primary)

                                        Button(action: {
                                            NSPasteboard.general.clearContents()
                                            NSPasteboard.general.setString("\(seed)", forType: .string)
                                        }) {
                                            Image(systemName: "doc.on.doc")
                                                .font(.caption2)
                                                .foregroundColor(.secondary)
                                        }
                                        .buttonStyle(.plain)
                                        .help("Copy seed")
                                    } else {
                                        Text("Auto / Unspecified")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }

                            GridRow {
                                Text("Status:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(liveTrack.status == .ready ? Color.green : Color.orange)
                                        .frame(width: 7, height: 7)
                                    Text(liveTrack.status.rawValue.capitalized)
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(liveTrack.status == .ready ? .green : .orange)
                                }
                            }

                            GridRow {
                                Text("Created At:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(formatDate(liveTrack.createdAt))
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    Text(Self.iso8601Formatter.string(from: liveTrack.createdAt))
                                        .font(.caption2.monospaced())
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Section 3: Audio File Storage
                    VStack(alignment: .leading, spacing: 8) {
                        Label("File Storage", systemImage: "folder")
                            .font(.subheadline.weight(.bold))
                            .foregroundColor(.primary)

                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Filename:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(liveTrack.audioFileName)
                                    .font(.caption.monospaced())
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                            }

                            HStack {
                                Text("Path:")
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.secondary)
                                Text(coordinator.persistence.audioFileURL(for: liveTrack).path)
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                            }

                            HStack(spacing: 8) {
                                Button(action: {
                                    coordinator.revealInFinder(liveTrack)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "folder")
                                        Text("Reveal in Finder")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button(action: {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(coordinator.persistence.audioFileURL(for: liveTrack).path, forType: .string)
                                }) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "doc.on.doc")
                                        Text("Copy Path")
                                    }
                                    .font(.caption)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                            .padding(.top, 4)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.primary.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    // Section 4: Gemini Suggestions
                    if let suggestions = liveTrack.suggestions {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Gemini Suggestions Snapshot", systemImage: "sparkles")
                                .font(.subheadline.weight(.bold))
                                .foregroundColor(.primary)

                            VStack(alignment: .leading, spacing: 8) {
                                suggestionRow(title: "Similar", text: suggestions.similar, color: .cyan)
                                suggestionRow(title: "Fun Twist", text: suggestions.fun, color: .orange)
                                suggestionRow(title: "Wildcard", text: suggestions.wild, color: .pink)
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.03))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(20)
            }

            Divider()

            // Footer Actions
            HStack(spacing: 12) {
                Button(action: {
                    coordinator.playExistingTrack(liveTrack)
                    if coordinator.inspectingTrack?.id == track.id {
                        coordinator.inspectingTrack = nil
                    }
                    dismiss()
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "play.fill")
                        Text("Play Track")
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .controlSize(.regular)

                Button(action: {
                    coordinator.toggleFavorite(for: liveTrack)
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: liveTrack.isFavorite ? "heart.fill" : "heart")
                            .foregroundColor(liveTrack.isFavorite ? .red : .secondary)
                        Text(liveTrack.isFavorite ? "Favorited" : "Favorite")
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)

                Spacer()
            }
            .padding(16)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 520, idealWidth: 560, minHeight: 480, maxHeight: 640)
    }

    private func suggestionRow(title: String, text: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.bold))
                .foregroundColor(color)
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func cleanModelName(_ raw: String) -> String {
        switch raw {
        case "lyria-3-clip-preview": return "Lyria 3 Clip"
        case "lyria-3-pro-preview": return "Lyria 3 Pro"
        default: return raw
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration <= 0 { return "Unknown / Auto" }
        let mins = Int(duration) / 60
        let secs = Int(duration) % 60
        return String(format: "%d:%02d (%.1fs)", mins, secs, duration)
    }

    private static let mediumDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()

    private static let iso8601Formatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        Self.mediumDateFormatter.string(from: date)
    }
}
