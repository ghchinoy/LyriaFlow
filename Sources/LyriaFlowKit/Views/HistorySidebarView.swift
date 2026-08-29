import SwiftUI

public enum SidebarTab: String, CaseIterable, Identifiable {
    case upNext = "Up Next"
    case history = "History"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .upNext: return "list.bullet.indent"
        case .history: return "clock.arrow.circlepath"
        }
    }
}

public struct HistorySidebarView: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @Binding var showingSettings: Bool
    @State private var selectedTab: SidebarTab = .upNext
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
            // Header with App Title & Settings
            HStack {
                Label("LyriaFlow", systemImage: "waveform")
                    .font(.headline.weight(.bold))
                    .foregroundColor(.primary)

                Spacer()

                Button(action: { showingSettings = true }) {
                    Image(systemName: "gearshape")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
                .buttonStyle(.plain)
                .help("Settings")
                .accessibilityLabel("LyriaFlow Settings")
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Segmented Tab Picker (Up Next vs History)
            Picker("Sidebar Section", selection: $selectedTab) {
                Text("Up Next\(coordinator.queue.isEmpty ? "" : " (\(coordinator.queue.count))")")
                    .tag(SidebarTab.upNext)

                Text("History")
                    .tag(SidebarTab.history)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            // Tab Content
            if selectedTab == .upNext {
                UpNextQueueView(coordinator: coordinator)
            } else {
                historyContent
            }

            Divider()

            // Footer MCP Server Status
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)

                Text(statusText)
                    .font(.caption)
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
                    .font(.caption.weight(.bold))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)
        }
        .frame(minWidth: 240, idealWidth: 280)
    }

    private var historyContent: some View {
        VStack(spacing: 0) {
            // Search Bar & Filter
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.caption)
                TextField("Search history...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.subheadline)

                if !searchText.isEmpty {
                    Button(action: { searchText = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { showOnlyFavorites.toggle() }) {
                    Image(systemName: showOnlyFavorites ? "heart.fill" : "heart")
                        .foregroundColor(showOnlyFavorites ? .red : .secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help(showOnlyFavorites ? "Show All Tracks" : "Show Favorites Only")
                .accessibilityLabel(showOnlyFavorites ? "Show all tracks" : "Show favorite tracks only")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(10)

            Divider()

            // Track List
            if filteredTracks.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "clock")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))
                    Text(coordinator.tracks.isEmpty ? "No history yet" : "No matches found")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
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
                        .fill(isCurrent ? Color.purple : Color.primary.opacity(0.08))
                        .frame(width: 24, height: 24)

                    Image(systemName: isPlaying ? "speaker.wave.2.fill" : "play.fill")
                        .font(.caption2.weight(.bold))
                        .foregroundColor(isCurrent ? .white : .primary)
                        .offset(x: isPlaying ? 0 : 0.5)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPlaying ? "Pause track" : "Play \(track.prompt)")

            VStack(alignment: .leading, spacing: 2) {
                Text(track.prompt)
                    .font(.subheadline.weight(isCurrent ? .semibold : .regular))
                    .foregroundColor(isCurrent ? .primary : .secondary)
                    .lineLimit(2)

                HStack(spacing: 4) {
                    Text(timeAgo(track.createdAt))
                        .font(.caption)
                        .foregroundColor(.secondary.opacity(0.8))

                    if track.isFavorite {
                        Image(systemName: "heart.fill")
                            .font(.caption2)
                            .foregroundColor(.red)
                    }
                }
            }

            Spacer(minLength: 2)

            if isHovered {
                Button(action: onToggleFavorite) {
                    Image(systemName: track.isFavorite ? "heart.fill" : "heart")
                        .font(.caption)
                        .foregroundColor(track.isFavorite ? .red : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(track.isFavorite ? "Unfavorite track" : "Favorite track")
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isCurrent ? Color.purple.opacity(0.12) : (isHovered ? Color.primary.opacity(0.04) : Color.clear))
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
