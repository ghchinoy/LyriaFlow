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
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(inspirationPrompts, id: \.0) { chip in
                        Button(action: {
                            promptText = chip.1
                        }) {
                            Text(chip.0)
                                .font(.system(size: 11, weight: .medium))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                                .cornerRadius(8)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            // Input Bar
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "music.quarternote.3")
                        .foregroundColor(.purple)
                        .font(.system(size: 14))

                    TextField("Describe the music track to generate...", text: $promptText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .onSubmit {
                            submitPrompt()
                        }

                    if !promptText.isEmpty {
                        Button(action: { promptText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                                .font(.system(size: 12))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.purple.opacity(0.3), lineWidth: 1)
                        )
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
                            .font(.system(size: 11, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .cornerRadius(8)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                // Generate Button
                Button(action: submitPrompt) {
                    HStack(spacing: 6) {
                        if coordinator.isGenerating {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "wand.and.stars")
                                .font(.system(size: 12, weight: .bold))
                        }
                        Text(coordinator.isGenerating ? "Generating..." : "Generate")
                            .font(.system(size: 12, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.purple)
                .disabled(coordinator.isGenerating || promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }

    private func cleanModelName(_ raw: String) -> String {
        switch raw {
        case "lyria-3-clip-preview": return "Lyria 3 Clip"
        case "lyria-3-pro-preview": return "Lyria 3 Pro"
        case "lyria-002": return "Lyria 2"
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
