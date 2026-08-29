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
    @Published public var inspectingTrack: Track? = nil
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
    public func generateAndPlay(prompt: String, modelId: String? = nil, seed: UInt32? = nil) async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        isGenerating = true
        generationMessage = "Composing track with Lyria AI..."
        errorMessage = nil

        let model = modelId ?? settings.defaultModelId
        let chosenSeed = seed ?? UInt32.random(in: 100_000...999_999_999)
        let fileName = "lyria_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).wav"

        var newTrack = Track(
            prompt: cleanPrompt,
            modelId: model,
            seed: chosenSeed,
            createdAt: Date(),
            audioFileName: fileName,
            status: .generating
        )

        do {
            let (fileURL, toolMsg) = try await mcpClient.generateMusic(
                prompt: cleanPrompt,
                modelId: model,
                localDir: persistence.tracksDirectory,
                fileName: fileName,
                seed: chosenSeed
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

            // Resume background queue pregeneration
            processQueueWorker()
        } catch {
            isGenerating = false
            generationMessage = ""
            errorMessage = "Generation failed: \(error.localizedDescription)"
            newTrack.status = .failed
            print("❌ Generation failed: \(error)")

            // Resume background queue worker
            processQueueWorker()
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
                    scheduleAutoPlaySuite(suggestions: existingSuggestions)
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

            // If auto-play is enabled and queue is empty, auto-enqueue a 3-track coherent suite!
            if self.settings.autoPlayEnabled && self.queue.isEmpty {
                self.scheduleAutoPlaySuite(suggestions: suggestions)
            }
        }
    }

    public func scheduleAutoPlaySuite(suggestions: GeminiSuggestions?) {
        guard settings.autoPlayEnabled, queue.isEmpty else { return }

        let basePrompt: String
        let originType: String

        if let suggestions = suggestions {
            let types: [SuggestionType] = [.similar, .fun, .wild]
            let pickedType = types.randomElement() ?? .similar
            switch pickedType {
            case .similar: basePrompt = suggestions.similar
            case .fun: basePrompt = suggestions.fun
            case .wild: basePrompt = suggestions.wild
            }
            originType = "Auto-Play: \(pickedType.rawValue)"
        } else if let currentTrack = currentTrack {
            basePrompt = currentTrack.prompt
            originType = "Auto-Play"
        } else {
            basePrompt = "Ambient melodic journey"
            originType = "Auto-Play"
        }

        queueMovementSuite(for: basePrompt, origin: originType)
    }

    public func scheduleAutoPlaySuggestion(suggestions: GeminiSuggestions) {
        scheduleAutoPlaySuite(suggestions: suggestions)
    }

    // MARK: - Up Next Queue Management
    public func addToQueue(
        prompt: String,
        modelId: String? = nil,
        seed: UInt32? = nil,
        origin: String? = nil,
        playNext: Bool = false
    ) {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        let model = modelId ?? settings.defaultModelId
        let item = QueuedTrack(
            prompt: cleanPrompt,
            modelId: model,
            seed: seed,
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

    /// Enqueues a cohesive 3-track progressive musical suite (Movement I, II, III)
    public func queueMovementSuite(
        for vibePrompt: String,
        origin: String,
        modelId: String? = nil
    ) {
        let cleanPrompt = vibePrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty else { return }

        let model = modelId ?? settings.defaultModelId
        let fallbackSuite = geminiEngine.fallbackMovementSuite(for: cleanPrompt)

        let item1 = QueuedTrack(
            prompt: fallbackSuite.movement1,
            modelId: model,
            origin: "\(origin) [1/3 Build]"
        )
        let item2 = QueuedTrack(
            prompt: fallbackSuite.movement2,
            modelId: model,
            origin: "\(origin) [2/3 Groove]"
        )
        let item3 = QueuedTrack(
            prompt: fallbackSuite.movement3,
            modelId: model,
            origin: "\(origin) [3/3 Climax]"
        )

        let itemIds = [item1.id, item2.id, item3.id]
        queue.append(contentsOf: [item1, item2, item3])
        processQueueWorker()

        // If Gemini API key is configured, dynamically generate progressive prompts and refine unstarted items
        let apiKey = settings.effectiveGeminiApiKey
        if !apiKey.isEmpty {
            Task { [weak self, cleanPrompt, itemIds] in
                guard let self = self else { return }
                let dynamicSuite = await self.geminiEngine.generateMovementSuite(
                    vibePrompt: cleanPrompt,
                    apiKey: apiKey,
                    modelName: self.settings.geminiModel
                )
                guard !Task.isCancelled else { return }

                // Update prompts for any queued tracks that haven't completed generation
                if let idx0 = self.queue.firstIndex(where: { $0.id == itemIds[0] }), case .queued = self.queue[idx0].status {
                    self.queue[idx0].prompt = dynamicSuite.movement1
                }
                if let idx1 = self.queue.firstIndex(where: { $0.id == itemIds[1] }), case .queued = self.queue[idx1].status {
                    self.queue[idx1].prompt = dynamicSuite.movement2
                }
                if let idx2 = self.queue.firstIndex(where: { $0.id == itemIds[2] }), case .queued = self.queue[idx2].status {
                    self.queue[idx2].prompt = dynamicSuite.movement3
                }
            }
        }
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
                    seed: item.seed,
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
                await generateAndPlay(prompt: item.prompt, modelId: item.modelId, seed: item.seed)
            }
        }
    }

    // MARK: - Queue Background Pre-Generation Worker
    public func processQueueWorker() {
        // If foreground generation is currently in progress, defer pre-generation until it completes
        if isGenerating { return }

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
                    fileName: targetItem.audioFileName,
                    seed: targetItem.seed
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
                // Continue pre-generating subsequent queued items despite failure
                self.processQueueWorker()
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
                        seed: nextItem.seed,
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
                    await generateAndPlay(prompt: nextItem.prompt, modelId: nextItem.modelId, seed: nextItem.seed)
                }
            }
        } else if settings.autoPlayEnabled {
            // Queue was empty; schedule 3-track coherent suite and start first movement
            scheduleAutoPlaySuite(suggestions: currentSuggestions)
            if !queue.isEmpty {
                let firstItem = queue.removeFirst()
                Task {
                    await generateAndPlay(prompt: firstItem.prompt, modelId: firstItem.modelId, seed: firstItem.seed)
                    processQueueWorker()
                }
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
        if inspectingTrack?.id == track.id {
            inspectingTrack = nil
        }
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
