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
                        .font(.subheadline.weight(.semibold))
                    Text("Up Next Queue")
                        .font(.subheadline.weight(.bold))
                }

                Spacer()

                if !coordinator.queue.isEmpty {
                    Text("\(coordinator.queue.count) track\(coordinator.queue.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Button(action: { coordinator.clearQueue() }) {
                        Text("Clear")
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Clear Queue")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.ultraThinMaterial)

            Divider()

            if coordinator.queue.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "music.note.list")
                        .font(.system(size: 32))
                        .foregroundColor(.secondary.opacity(0.4))

                    Text("Queue is empty")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(coordinator.settings.autoPlayEnabled
                         ? "Auto-Play is ON: Gemini suggestions will automatically queue and pre-generate."
                         : "Click 'Queue' on any Gemini suggestion or inspiration chip to line up tracks.")
                        .font(.caption)
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
                        .fill(Color.purple.opacity(0.18))
                        .frame(width: 24, height: 24)

                    if isHovered {
                        Image(systemName: "play.fill")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.purple)
                    } else {
                        Text("\(index + 1)")
                            .font(.caption2.monospacedDigit().weight(.bold))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .buttonStyle(.plain)
            .help("Play Now")
            .accessibilityLabel("Play \(item.prompt) now")

            // Content
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    if let origin = item.origin {
                        Text(origin)
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.purple.opacity(0.18))
                            .foregroundColor(.purple)
                            .clipShape(Capsule())
                    }

                    statusBadge
                }

                Text(item.prompt)
                    .font(.subheadline)
                    .foregroundColor(.primary)
                    .lineLimit(2)
            }

            Spacer(minLength: 4)

            // Reorder & Remove Controls on hover
            if isHovered {
                HStack(spacing: 4) {
                    if index > 0 {
                        Button(action: onMoveUp) {
                            Image(systemName: "chevron.up")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Move Up")
                        .accessibilityLabel("Move \(item.prompt) up")
                    }

                    if index < totalCount - 1 {
                        Button(action: onMoveDown) {
                            Image(systemName: "chevron.down")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Move Down")
                        .accessibilityLabel("Move \(item.prompt) down")
                    }

                    Button(action: onRemove) {
                        Image(systemName: "xmark")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove from Queue")
                    .accessibilityLabel("Remove \(item.prompt) from queue")
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? Color.primary.opacity(0.04) : Color.clear)
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
            .font(.caption2.weight(.bold))
            .foregroundColor(.green)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.green.opacity(0.18))
            .clipShape(Capsule())
        case .generating:
            HStack(spacing: 3) {
                ProgressView()
                    .scaleEffect(0.4)
                    .frame(width: 8, height: 8)
                Text("Generating...")
            }
            .font(.caption2.weight(.semibold))
            .foregroundColor(.orange)
            .padding(.horizontal, 5)
            .padding(.vertical, 1.5)
            .background(Color.orange.opacity(0.18))
            .clipShape(Capsule())
        case .queued:
            Text("Queued")
                .font(.caption2)
                .foregroundColor(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.secondary.opacity(0.18))
                .clipShape(Capsule())
        case .failed(let msg):
            Text("Failed: \(msg.prefix(15))")
                .font(.caption2)
                .foregroundColor(.red)
                .padding(.horizontal, 5)
                .padding(.vertical, 1.5)
                .background(Color.red.opacity(0.18))
                .clipShape(Capsule())
        }
    }
}
