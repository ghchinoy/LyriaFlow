import SwiftUI

public struct UpNextQueueView: View {
    @ObservedObject var coordinator: PlaybackCoordinator

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "list.bullet.indent")
                        .foregroundColor(.purple)
                    Text("Up Next Queue")
                        .font(.system(size: 13, weight: .bold))
                }

                Spacer()

                if !coordinator.queue.isEmpty {
                    Text("\(coordinator.queue.count) track\(coordinator.queue.count == 1 ? "" : "s")")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)

                    Button(action: { coordinator.clearQueue() }) {
                        Text("Clear")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Queue")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))

            Divider()

            if coordinator.queue.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("Queue is empty")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)

                    Text(coordinator.settings.autoPlayEnabled
                         ? "Auto-Play is ON: Gemini suggestions will automatically queue and pre-generate."
                         : "Click 'Queue' on any Gemini suggestion or inspiration chip to line up tracks.")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 16)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(coordinator.queue.enumerated()), id: \.element.id) { index, item in
                        QueuedTrackRow(
                            item: item,
                            index: index,
                            totalCount: coordinator.queue.count,
                            onPlayNow: { coordinator.playQueueItemNow(id: item.id) },
                            onMoveUp: { coordinator.moveQueueItemUp(id: item.id) },
                            onMoveDown: { coordinator.moveQueueItemDown(id: item.id) },
                            onRemove: { coordinator.removeFromQueue(id: item.id) }
                        )
                        .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                    }
                    .onMove { indices, newOffset in
                        coordinator.moveQueueItem(from: indices, to: newOffset)
                    }
                }
                .listStyle(.sidebar)
            }
        }
    }
}

struct QueuedTrackRow: View {
    let item: QueuedTrack
    let index: Int
    let totalCount: Int
    let onPlayNow: () -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onRemove: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            // Index & Play button
            Button(action: onPlayNow) {
                ZStack {
                    Circle()
                        .fill(Color.purple.opacity(0.2))
                        .frame(width: 22, height: 22)

                    if isHovered {
                        Image(systemName: "play.fill")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.purple)
                    } else {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Play Now")

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let origin = item.origin {
                        Text(origin)
                            .font(.system(size: 9, weight: .semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.purple.opacity(0.15))
                            .foregroundColor(.purple)
                            .cornerRadius(4)
                    }

                    statusBadge
                }

                Text(item.prompt)
                    .font(.system(size: 11))
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Reorder & Remove Controls on hover
            if isHovered {
                HStack(spacing: 2) {
                    if index > 0 {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Move Up")
                    }

                    if index < totalCount - 1 {
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.system(size: 9))
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Move Down")
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Queue")
                }
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? Color.white.opacity(0.04) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .contextMenu {
            Button("Play Immediately", action: onPlayNow)
            if index > 0 {
                Button("Move Up", action: onMoveUp)
            }
            if index < totalCount - 1 {
                Button("Move Down", action: onMoveDown)
            }
            Divider()
            Button("Remove from Queue", role: .destructive, action: onRemove)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        switch item.status {
        case .ready:
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                Text("Ready")
            }
            .font(.system(size: 9, weight: .bold))
            .foregroundColor(.green)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Color.green.opacity(0.15))
            .cornerRadius(4)
        case .generating:
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 8, height: 8)
                Text("Generating...")
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(Color.orange.opacity(0.15))
            .cornerRadius(4)
        case .queued:
            Text("Queued")
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.secondary.opacity(0.15))
                .cornerRadius(4)
        case .failed(let msg):
            Text("Failed: \(msg.prefix(15))")
                .font(.system(size: 9))
                .foregroundColor(.red)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(Color.red.opacity(0.15))
                .cornerRadius(4)
        }
    }
}
