import SwiftUI

public struct WaveformVisualizerView: View {
    public let powerLevels: [Float]
    public let isPlaying: Bool

    public init(powerLevels: [Float], isPlaying: Bool) {
        self.powerLevels = powerLevels
        self.isPlaying = isPlaying
    }

    public var body: some View {
        ZStack {
            // Ambient dynamic glow behind visualizer during active playback
            if isPlaying {
                RoundedRectangle(cornerRadius: 20)
                    .fill(
                        RadialGradient(
                            colors: [
                                Color.purple.opacity(0.20),
                                Color.cyan.opacity(0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 20,
                            endRadius: 180
                        )
                    )
                    .frame(height: 140)
                    .blur(radius: 14)
                    .transition(.opacity)
            }

            // Glassmorphic Spectrum Canvas
            VStack(spacing: 8) {
                HStack(alignment: .center, spacing: 4) {
                    ForEach(0..<AudioEngine.barCount, id: \.self) { idx in
                        let level = idx < powerLevels.count ? CGFloat(powerLevels[idx]) : CGFloat(0.04)
                        let minHeight: CGFloat = 6
                        let maxHeight: CGFloat = 100
                        let barHeight = isPlaying ? minHeight + (maxHeight - minHeight) * level : minHeight

                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: isPlaying
                                        ? [
                                            Color.purple.opacity(0.9),
                                            Color.indigo.opacity(0.95),
                                            Color.cyan.opacity(0.9)
                                        ]
                                        : [
                                            Color.secondary.opacity(0.25),
                                            Color.secondary.opacity(0.35)
                                        ],
                                    startPoint: .bottom,
                                    endPoint: .top
                                )
                            )
                            .frame(width: 6, height: barHeight)
                            .animation(
                                .spring(response: 0.16, dampingFraction: 0.58, blendDuration: 0.08),
                                value: barHeight
                            )
                            .shadow(
                                color: isPlaying ? Color.cyan.opacity(0.35) : .clear,
                                radius: 4,
                                x: 0,
                                y: 0
                            )
                    }
                }
                .frame(height: 110)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 3)
        }
        .animation(.easeInOut(duration: 0.25), value: isPlaying)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio Spectrum Visualizer")
        .accessibilityValue(isPlaying ? "Playing, active 32-bar audio spectrum" : "Paused, resting baseline")
        .frame(maxWidth: 560)
        .frame(height: 140)
        .padding(.vertical, 8)
    }
}
