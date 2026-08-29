import SwiftUI

public struct HistorySidebarView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @Binding var showingSettings: Bool
    @State private var searchText: String = ""
    @State private var showOnlyFavorites: Bool = false

    public init(coordinator: PlaybackCoordinator, showingSettings: Binding<Bool>) {
        self.coordinator = coordinator
        self._showingSettings = showingSettings
    }

    var filteredTracks: [Track] {
        coordinator.tracks.filter { track in
            let matchesSearch = searchText.isEmpty || track.prompt.localizedCaseInsensitiveContains(searchText)
            let matchesFav = !showOnlyFavorites || track.isFavorite
            return matchesSearch && matchesFav
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header with title and filter
            VStack(spacing: 8) {
                HStack {
                    Label("LyriaFlow", systemImage: "waveform")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)

                    Spacer()

                    Button(action: { showOnlyFavorites.toggle() }) {
                        Image(systemName: showOnlyFavorites ? "heart.fill" : "heart")
                            .foregroundColor(showOnlyFavorites ? .red : .secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help(showOnlyFavorites ? "Show All Tracks" : "Show Favorites Only")

                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                }

                // Search Bar
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                        .font(.system(size: 11))
                    TextField("Search tracks...", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(6)
            }
            .padding(12)

            Divider()

            // Track List
            if filteredTracks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 24))
                        .foregroundColor(.secondary.opacity(0.6))
                    Text(coordinator.tracks.isEmpty ? "No tracks yet" : "No matches found")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List(filteredTracks) { track in
                    TrackRowView(
                        track: track,
                        isCurrent: coordinator.currentTrack?.id == track.id,
                        isPlaying: coordinator.currentTrack?.id == track.id && coordinator.audioEngine.isPlaying,
                        onPlay: { coordinator.playExistingTrack(track) },
                        onToggleFavorite: { coordinator.toggleFavorite(for: track) },
                        onDelete: { coordinator.deleteTrack(track) },
                        onReveal: { coordinator.revealInFinder(track) },
                        onCopyPrompt: {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(track.prompt, forType: .string)
                        }
                    )
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                .listStyle(.sidebar)
            }

            Divider()

            // Footer MCP Server Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                    .lineLimit(1)

                Spacer()

                if case .error = coordinator.serverStatus {
                    Button("Retry") {
                        Task {
                            await coordinator.connectAndVerifyServer()
                        }
                    }
                    .buttonStyle(.borderless)
                    .font(.system(size: 10, weight: .bold))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 220, idealWidth: 260)
    }

    private var statusColor: Color {
        switch coordinator.serverStatus {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch coordinator.serverStatus {
        case .connected(let info, _):
            return "MCP: \(info.name) \(info.version ?? "")"
        case .connecting:
            return "MCP: Connecting..."
        case .disconnected:
            return "MCP: Disconnected"
        case .error:
            return "MCP: Offline"
        }
    }
}

struct TrackRowView: View {
    let track: Track
    let isCurrent: Bool
    let isPlaying: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void
    let onDelete: () -> Void
    let onReveal: () -> Void
    let onCopyPrompt: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Play indicator icon
            Button(action: onPlay) {
                ZStack {
                    Circle()
                        .fill(isCurrent ? Color.purple : Color.secondary.opacity(0.15))
                        .frame(width: 24, height: 24)

                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(isCurrent ? .white : .primary)
                        .offset(x: isPlaying ? 0 : 0.5)
                }
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(track.prompt)
                    .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(timeAgo(track.createdAt))
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.8))

                    if track.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 8))
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onToggleFavorite) {
                    Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 10))
                        .foregroundColor(track.isFavorite ? .red : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isCurrent ? Color.purple.opacity(0.1) : (isHovered ? Color.white.opacity(0.04) : Color.clear))
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture {
            onPlay()
        }
        .contextMenu {
            Button("Play Track", action: onPlay)
            Button("Copy Prompt", action: onCopyPrompt)
            Button(track.isFavorite ? "Unfavorite" : "Favorite", action: onToggleFavorite)
            Button("Reveal in Finder", action: onReveal)
            Divider()
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private func timeAgo(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
