import SwiftUI

public struct WaveformVisualizerView: View {
    public let powerLevels: [Float]
    public let isPlaying: Bool

    public init(powerLevels: [Float], isPlaying: Bool) {
        self.powerLevels = powerLevels
        self.isPlaying = isPlaying
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 4) {
            ForEach(0..<powerLevels.count, id: \.self) { idx in
                let level = CGFloat(powerLevels[idx])
                let minHeight: CGFloat = 8
                let maxHeight: CGFloat = 72
                let barHeight = isPlaying ? minHeight + (maxHeight - minHeight) * level : 10

                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: isPlaying
                                ? [Color.purple.opacity(0.8), Color.cyan.opacity(0.9), Color.pink.opacity(0.85)]
                                : [Color.secondary.opacity(0.2), Color.secondary.opacity(0.3)],
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                    .frame(width: 5, height: barHeight)
                    .animation(.spring(response: 0.18, dampingFraction: 0.6, blendDuration: 0.1), value: barHeight)
                    .shadow(color: isPlaying ? Color.cyan.opacity(0.3) : .clear, radius: 4, x: 0, y: 0)
            }
        }
        .frame(height: 80)
        .padding(.vertical, 8)
    }
}
