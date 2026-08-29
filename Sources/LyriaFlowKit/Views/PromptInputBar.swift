import SwiftUI

public struct PromptInputBar: View {
    @ObservedObject var coordinator: PlaybackCoordinator
    @State private var promptText: String = ""
    @State private var selectedModel: String = "lyria-3-clip-preview"

    let inspirationPrompts = [
        ("☕️ Lo-Fi Chill", "Chill lo-fi hip hop beat with warm rhodes keys, subtle vinyl crackle and mellow bassline"),
        ("⚡️ Cyberpunk", "Futuristic synthwave with pulsing analog arpeggios, punchy kicks, and neon synth lead"),
        ("🌌 Ambient", "Ethereal ambient soundscape with shimmering reverb, meditative pads, and soft bell tones"),
        ("🎷 Jazz Lounge", "Smooth nocturnal jazz with muted trumpet, acoustic upright bass, and gentle brush drums")
    ]

    public init(coordinator: PlaybackCoordinator) {
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Inspiration chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    Text("Try:")
                        .font(.caption.weight(.medium))
                        .foregroundColor(.secondary)

                    ForEach(inspirationPrompts, id: \.0) { chip in
                        Button(action: {
                            promptText = chip.1
                        }) {
                            Text(chip.0)
                                .font(.caption.weight(.medium))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Inspiration prompt: \(chip.0)")
                    }
                }
            }

            // Input Bar
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "music.quarternote.3")
                        .foregroundColor(.purple)
                        .font(.subheadline)

                    TextField("Describe the music track to generate...", text: $promptText)
                        .textFieldStyle(.plain)
                        .font(.body)
                        .onSubmit {
                            submitPrompt()
                        }

                    if !promptText.isEmpty {
                        Button(action: { promptText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear prompt")
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.purple.opacity(0.35), lineWidth: 1)
                )

                // Model Menu
                Menu {
                    ForEach(AppSettings.availableLyriaModels, id: \.self) { model in
                        Button(action: { selectedModel = model }) {
                            HStack {
                                Text(model)
                                if selectedModel == model {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(cleanModelName(selectedModel))
                            .font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down")
                            .font(.caption2)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .accessibilityLabel("Select Lyria AI model")

                // Generate Button
                Button(action: submitPrompt) {
                    HStack(spacing: 6) {
                        if coordinator.isGenerating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.subheadline.weight(.bold))
                        }
                        Text(coordinator.isGenerating ? "Generating..." : "Generate")
                            .font(.subheadline.weight(.semibold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.purple)
                .disabled(coordinator.isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityLabel(coordinator.isGenerating ? "Generating music track" : "Generate music track")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private func cleanModelName(_ raw: String) -> String {
        switch raw {
        case "lyria-3-clip-preview": return "Lyria 3 Clip"
        case "lyria-3-pro-preview": return "Lyria 3 Pro"
        default: return raw
        }
    }

    private func submitPrompt() {
        let p = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        Task {
            await coordinator.generateAndPlay(prompt: p, modelId: selectedModel)
        }
    }
}
