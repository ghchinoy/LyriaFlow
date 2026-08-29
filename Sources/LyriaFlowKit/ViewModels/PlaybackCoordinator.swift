import Foundation
import SwiftUI
import Combine

@MainActor
public final class PlaybackCoordinator: ObservableObject {
    @Published public var serverStatus: MCPServerStatus = .disconnected
    @Published public var currentTrack: Track? = nil
    @Published public var tracks: [Track] = []
    @Published public var isGenerating: Bool = false
    @Published public var generationMessage: String = ""
    @Published public var currentSuggestions: GeminiSuggestions? = nil
    @Published public var isLoadingSuggestions: Bool = false
    @Published public var pregeneratedTrack: Track? = nil
    @Published public var pregeneratingPrompt: String? = nil
    @Published public var pregenerationType: SuggestionType? = nil
    @Published public var errorMessage: String? = nil

    public let audioEngine: AudioEngine
    public let mcpClient: MCPClient
    public let geminiEngine: GeminiSuggestionEngine
    public let persistence: PersistenceStore
    public let settings: AppSettings

    private var pregenerationTask: Task<Void, Never>?
    private var suggestionsTask: Task<Void, Never>?

    public init(
        audioEngine: AudioEngine? = nil,
        mcpClient: MCPClient = MCPClient(),
        geminiEngine: GeminiSuggestionEngine = GeminiSuggestionEngine(),
        persistence: PersistenceStore = .shared,
        settings: AppSettings = .shared
    ) {
        self.audioEngine = audioEngine ?? AudioEngine()
        self.mcpClient = mcpClient
        self.geminiEngine = geminiEngine
        self.persistence = persistence
        self.settings = settings

        self.tracks = persistence.loadTracks()
        self.audioEngine.volume = Float(settings.volume)
        self.audioEngine.isLooping = settings.loopEnabled

        setupAudioCallbacks()
    }

    private func setupAudioCallbacks() {
        audioEngine.onTrackFinished = { [weak self] in
            Task { @MainActor in
                self?.handleTrackDidFinish()
            }
        }
    }

    // MARK: - Server Lifecycle & Verification
    public func connectAndVerifyServer() async {
        serverStatus = .connecting
        let binaryPath = settings.effectiveMcpBinaryPath
        do {
            let (serverInfo, tools) = try await mcpClient.initializeAndVerify(binaryPath: binaryPath)
            serverStatus = .connected(serverInfo: serverInfo, tools: tools)
            errorMessage = nil
            print("✅ MCP Server connected: \(serverInfo.name) (\(tools.count) tools)")
        } catch {
            serverStatus = .error(error.localizedDescription)
            errorMessage = "MCP Server connection failed: \(error.localizedDescription)"
            print("❌ MCP Server connection error: \(error)")
        }
    }

    // MARK: - Track Generation & Playback
    public func generateAndPlay(prompt: String, modelId: String? = nil) async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        // Cancel any pending pregeneration
        pregenerationTask?.cancel()
        pregenerationTask = nil
        pregeneratedTrack = nil
        pregeneratingPrompt = nil
        pregenerationType = nil

        isGenerating = true
        generationMessage = "Composing track with Lyria AI..."
        errorMessage = nil

        let model = modelId ?? settings.defaultModelId
        let fileName = "lyria_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"

        var newTrack = Track(
            prompt: cleanPrompt,
            modelId: model,
            createdAt: Date(),
            audioFileName: fileName,
            status: .generating
        )

        do {
            let (fileURL, toolMsg) = try await mcpClient.generateMusic(
                prompt: cleanPrompt,
                modelId: model,
                localDir: persistence.tracksDirectory,
                fileName: fileName
            )
            print("🎵 Generated file: \(fileURL.path), message: \(toolMsg)")

            try audioEngine.loadAndPlay(url: fileURL)
            newTrack.duration = audioEngine.duration
            newTrack.status = .ready

            // Insert into history
            tracks.insert(newTrack, at: 0)
            persistence.saveTracks(tracks)
            currentTrack = newTrack
            isGenerating = false
            generationMessage = ""

            // Trigger Gemini suggestions
            fetchSuggestionsForPlayingTrack(track: newTrack)
        } catch {
            isGenerating = false
            generationMessage = ""
            errorMessage = "Generation failed: \(error.localizedDescription)"
            newTrack.status = .failed
            print("❌ Generation failed: \(error)")
        }
    }

    public func playExistingTrack(_ track: Track) {
        let fileURL = persistence.audioFileURL(for: track)
        do {
            try audioEngine.loadAndPlay(url: fileURL)
            currentTrack = track
            errorMessage = nil

            // Reset or fetch suggestions
            if let existingSuggestions = track.suggestions {
                currentSuggestions = existingSuggestions
                if settings.autoPlayEnabled {
                    scheduleAutoPlayPregeneration(suggestions: existingSuggestions)
                }
            } else {
                fetchSuggestionsForPlayingTrack(track: track)
            }
        } catch {
            errorMessage = "Failed to play track: \(error.localizedDescription)"
        }
    }

    // MARK: - Gemini Suggestions & Background Pre-generation
    public func fetchSuggestionsForPlayingTrack(track: Track) {
        suggestionsTask?.cancel()
        isLoadingSuggestions = true
        currentSuggestions = nil

        suggestionsTask = Task {
            let suggestions = await geminiEngine.generateSuggestions(
                currentPrompt: track.prompt,
                apiKey: settings.effectiveGeminiApiKey,
                modelName: settings.geminiModel
            )

            guard !Task.isCancelled else { return }

            self.currentSuggestions = suggestions
            self.isLoadingSuggestions = false

            // Update track in store
            if let idx = self.tracks.firstIndex(where: { $0.id == track.id }) {
                self.tracks[idx].suggestions = suggestions
                self.persistence.saveTracks(self.tracks)
            }
            if self.currentTrack?.id == track.id {
                self.currentTrack?.suggestions = suggestions
            }

            // If auto-play is enabled, begin background pregeneration
            if self.settings.autoPlayEnabled {
                self.scheduleAutoPlayPregeneration(suggestions: suggestions)
            }
        }
    }

    public func scheduleAutoPlayPregeneration(suggestions: GeminiSuggestions) {
        // Randomly pick one of the 3 suggestions for continuous auto-play
        let types: [SuggestionType] = [.similar, .fun, .wild]
        let pickedType = types.randomElement() ?? .similar
        let pickedPrompt: String
        switch pickedType {
        case .similar: pickedPrompt = suggestions.similar
        case .fun: pickedPrompt = suggestions.fun
        case .wild: pickedPrompt = suggestions.wild
        }

        startPregeneration(prompt: pickedPrompt, type: pickedType)
    }

    public func selectSuggestion(_ type: SuggestionType, playImmediately: Bool = false) {
        guard let suggestions = currentSuggestions else { return }
        let selectedPrompt: String
        switch type {
        case .similar: selectedPrompt = suggestions.similar
        case .fun: selectedPrompt = suggestions.fun
        case .wild: selectedPrompt = suggestions.wild
        }

        if playImmediately {
            Task {
                await generateAndPlay(prompt: selectedPrompt)
            }
        } else {
            // Queue and pre-generate this specific suggestion
            startPregeneration(prompt: selectedPrompt, type: type)
        }
    }

    private func startPregeneration(prompt: String, type: SuggestionType) {
        pregenerationTask?.cancel()
        pregeneratedTrack = nil
        pregeneratingPrompt = prompt
        pregenerationType = type

        pregenerationTask = Task {
            let fileName = "lyria_pregen_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"
            let model = settings.defaultModelId

            print("🔄 Pre-generating next track in background: \"\(prompt)\"")

            do {
                let (fileURL, _) = try await mcpClient.generateMusic(
                    prompt: prompt,
                    modelId: model,
                    localDir: persistence.tracksDirectory,
                    fileName: fileName
                )

                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }

                let pregen = Track(
                    prompt: prompt,
                    modelId: model,
                    createdAt: Date(),
                    audioFileName: fileName,
                    status: .pregenerated
                )

                self.pregeneratedTrack = pregen
                print("✨ Background pre-generation complete! Ready in queue.")
            } catch {
                print("⚠️ Background pre-generation failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleTrackDidFinish() {
        if settings.loopEnabled {
            // Loop handled by AudioEngine numberOfLoops
            return
        }

        guard settings.autoPlayEnabled else { return }

        // If we have a pregenerated track ready, play it instantly!
        if let nextTrack = pregeneratedTrack {
            let fileURL = persistence.audioFileURL(for: nextTrack)
            do {
                try audioEngine.loadAndPlay(url: fileURL)
                var readyTrack = nextTrack
                readyTrack.duration = audioEngine.duration
                readyTrack.status = .ready

                tracks.insert(readyTrack, at: 0)
                persistence.saveTracks(tracks)
                currentTrack = readyTrack

                pregeneratedTrack = nil
                pregeneratingPrompt = nil
                pregenerationType = nil

                fetchSuggestionsForPlayingTrack(track: readyTrack)
            } catch {
                print("❌ Failed to play pregenerated track: \(error)")
            }
        } else if let prompt = pregeneratingPrompt {
            // Pre-generation was still in flight; wait for it to finish and play
            generationMessage = "Queueing next track..."
            isGenerating = true
            Task {
                await generateAndPlay(prompt: prompt)
            }
        } else if let suggestions = currentSuggestions {
            // Fallback pick
            let prompt = [suggestions.similar, suggestions.fun, suggestions.wild].randomElement() ?? suggestions.similar
            Task {
                await generateAndPlay(prompt: prompt)
            }
        }
    }

    // MARK: - Track Management
    public func toggleFavorite(for track: Track) {
        if let idx = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[idx].isFavorite.toggle()
            if currentTrack?.id == track.id {
                currentTrack?.isFavorite = tracks[idx].isFavorite
            }
            persistence.saveTracks(tracks)
        }
    }

    public func deleteTrack(_ track: Track) {
        if currentTrack?.id == track.id {
            audioEngine.stop()
            currentTrack = nil
            currentSuggestions = nil
        }
        persistence.deleteTrack(track, tracks: &tracks)
    }

    public func revealInFinder(_ track: Track) {
        persistence.revealInFinder(for: track)
    }
}
