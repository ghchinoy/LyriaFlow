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
    @Published public var queue: [QueuedTrack] = []
    @Published public var errorMessage: String? = nil

    public let audioEngine: AudioEngine
    public let mcpClient: MCPClient
    public let geminiEngine: GeminiSuggestionEngine
    public let persistence: PersistenceStore
    public let settings: AppSettings

    private var queueWorkerTask: Task<Void, Never>?
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

    // MARK: - Direct Track Generation & Playback
    public func generateAndPlay(prompt: String, modelId: String? = nil) async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

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

            if let existingSuggestions = track.suggestions {
                currentSuggestions = existingSuggestions
                if settings.autoPlayEnabled && queue.isEmpty {
                    scheduleAutoPlaySuggestion(suggestions: existingSuggestions)
                }
            } else {
                fetchSuggestionsForPlayingTrack(track: track)
            }
        } catch {
            errorMessage = "Failed to play track: \(error.localizedDescription)"
        }
    }

    // MARK: - Gemini Suggestions & Queue Integration
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

            // If auto-play is enabled and queue is empty, auto-enqueue one of the suggestions!
            if self.settings.autoPlayEnabled && self.queue.isEmpty {
                self.scheduleAutoPlaySuggestion(suggestions: suggestions)
            }
        }
    }

    public func scheduleAutoPlaySuggestion(suggestions: GeminiSuggestions) {
        let types: [SuggestionType] = [.similar, .fun, .wild]
        let pickedType = types.randomElement() ?? .similar
        let pickedPrompt: String
        switch pickedType {
        case .similar: pickedPrompt = suggestions.similar
        case .fun: pickedPrompt = suggestions.fun
        case .wild: pickedPrompt = suggestions.wild
        }

        addToQueue(
            prompt: pickedPrompt,
            modelId: settings.defaultModelId,
            origin: "Auto-Play: \(pickedType.rawValue)"
        )
    }

    // MARK: - Up Next Queue Management
    public func addToQueue(
        prompt: String,
        modelId: String? = nil,
        origin: String? = nil,
        playNext: Bool = false
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        let model = modelId ?? settings.defaultModelId
        let item = QueuedTrack(
            prompt: cleanPrompt,
            modelId: model,
            origin: origin,
            status: .queued
        )

        if playNext {
            queue.insert(item, at: 0)
        } else {
            queue.append(item)
        }

        processQueueWorker()
    }

    public func removeFromQueue(id: UUID) {
        if let idx = queue.firstIndex(where: { $0.id == id }) {
            let item = queue[idx]
            if case .ready(let fileURL, _) = item.status {
                try? FileManager.default.removeItem(at: fileURL)
            }
            queue.remove(at: idx)
            processQueueWorker()
        }
    }

    public func clearQueue() {
        queueWorkerTask?.cancel()
        queueWorkerTask = nil
        for item in queue {
            if case .ready(let fileURL, _) = item.status {
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        queue.removeAll()
    }

    public func moveQueueItem(from offsets: IndexSet, to destination: Int) {
        queue.move(fromOffsets: offsets, toOffset: destination)
        processQueueWorker()
    }

    public func moveQueueItemUp(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }), idx > 0 else { return }
        queue.swapAt(idx, idx - 1)
        processQueueWorker()
    }

    public func moveQueueItemDown(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }), idx < queue.count - 1 else { return }
        queue.swapAt(idx, idx + 1)
        processQueueWorker()
    }

    public func playQueueItemNow(id: UUID) {
        guard let idx = queue.firstIndex(where: { $0.id == id }) else { return }
        let item = queue.remove(at: idx)

        if case .ready(let fileURL, _) = item.status {
            do {
                try audioEngine.loadAndPlay(url: fileURL)
                let newTrack = Track(
                    prompt: item.prompt,
                    modelId: item.modelId,
                    createdAt: Date(),
                    duration: audioEngine.duration,
                    audioFileName: item.audioFileName,
                    status: .ready
                )
                tracks.insert(newTrack, at: 0)
                persistence.saveTracks(tracks)
                currentTrack = newTrack
                fetchSuggestionsForPlayingTrack(track: newTrack)
                processQueueWorker()
            } catch {
                errorMessage = "Failed to play queued track: \(error.localizedDescription)"
            }
        } else {
            Task {
                await generateAndPlay(prompt: item.prompt, modelId: item.modelId)
            }
        }
    }

    // MARK: - Queue Background Pre-Generation Worker
    public func processQueueWorker() {
        // Find the first queued item that needs pre-generation
        guard let targetIndex = queue.firstIndex(where: { $0.status == .queued }) else { return }
        let targetItem = queue[targetIndex]

        // Don't start another pre-generation task if one is already generating this item
        if queue.contains(where: { $0.status.isGenerating }) {
            return
        }

        queue[targetIndex].status = .generating
        print("🔄 Pre-generating queue item [\(targetIndex + 1)/\(queue.count)]: \"\(targetItem.prompt)\"")

        queueWorkerTask?.cancel()
        queueWorkerTask = Task {
            do {
                let (fileURL, _) = try await mcpClient.generateMusic(
                    prompt: targetItem.prompt,
                    modelId: targetItem.modelId,
                    localDir: persistence.tracksDirectory,
                    fileName: targetItem.audioFileName
                )

                guard !Task.isCancelled else {
                    try? FileManager.default.removeItem(at: fileURL)
                    return
                }

                if let idx = self.queue.firstIndex(where: { $0.id == targetItem.id }) {
                    self.queue[idx].status = .ready(fileURL: fileURL, duration: 30.0)
                    print("✨ Queue item ready: \"\(targetItem.prompt)\"")
                }

                // If there's another queued item, continue pre-generating
                self.processQueueWorker()
            } catch {
                if let idx = self.queue.firstIndex(where: { $0.id == targetItem.id }) {
                    self.queue[idx].status = .failed(error.localizedDescription)
                    print("⚠️ Queue pre-generation failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handleTrackDidFinish() {
        if settings.loopEnabled {
            return
        }

        guard settings.autoPlayEnabled || !queue.isEmpty else { return }

        if !queue.isEmpty {
            let nextItem = queue.removeFirst()

            if case .ready(let fileURL, _) = nextItem.status {
                do {
                    try audioEngine.loadAndPlay(url: fileURL)
                    let readyTrack = Track(
                        prompt: nextItem.prompt,
                        modelId: nextItem.modelId,
                        createdAt: Date(),
                        duration: audioEngine.duration,
                        audioFileName: nextItem.audioFileName,
                        status: .ready
                    )

                    tracks.insert(readyTrack, at: 0)
                    persistence.saveTracks(tracks)
                    currentTrack = readyTrack

                    fetchSuggestionsForPlayingTrack(track: readyTrack)
                    processQueueWorker()
                } catch {
                    print("❌ Failed to play ready queued track: \(error)")
                }
            } else {
                // Was queued/generating; generate and play immediately
                Task {
                    await generateAndPlay(prompt: nextItem.prompt, modelId: nextItem.modelId)
                }
            }
        } else if let suggestions = currentSuggestions {
            // Queue was empty; pick suggestion and play
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
