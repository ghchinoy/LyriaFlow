import XCTest
@testable import LyriaFlowKit

final class LyriaFlowTests: XCTestCase {

    func testTrackModelCreationAndCodable() throws {
        let suggestions = GeminiSuggestions(
            similar: "Smooth jazz chillout with rhodes",
            fun: "Funky electro swing variation",
            wild: "Dark cyber industrial techno"
        )

        let track = Track(
            prompt: "Test Prompt for Lyria AI",
            modelId: "lyria-3-clip-preview",
            seed: 12345,
            duration: 30.5,
            audioFileName: "test_file.mp3",
            suggestions: suggestions,
            isFavorite: true,
            status: .ready
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(track)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(Track.self, from: data)

        XCTAssertEqual(decoded.id, track.id)
        XCTAssertEqual(decoded.prompt, "Test Prompt for Lyria AI")
        XCTAssertEqual(decoded.modelId, "lyria-3-clip-preview")
        XCTAssertEqual(decoded.seed, 12345)
        XCTAssertEqual(decoded.duration, 30.5)
        XCTAssertEqual(decoded.audioFileName, "test_file.mp3")
        XCTAssertEqual(decoded.isFavorite, true)
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertEqual(decoded.suggestions?.similar, "Smooth jazz chillout with rhodes")
        XCTAssertEqual(decoded.suggestions?.fun, "Funky electro swing variation")
        XCTAssertEqual(decoded.suggestions?.wild, "Dark cyber industrial techno")
    }

    func testQueuedTrackLifecycleAndReordering() {
        var item1 = QueuedTrack(prompt: "Track 1", origin: "Similar")
        let item2 = QueuedTrack(prompt: "Track 2", origin: "Fun Twist")
        let item3 = QueuedTrack(prompt: "Track 3", origin: "Wildcard")

        XCTAssertEqual(item1.status, .queued)
        XCTAssertFalse(item1.status.isReady)
        XCTAssertFalse(item1.status.isGenerating)
        XCTAssertTrue(item1.audioFileName.hasSuffix(".mp3"))

        item1.status = .generating
        XCTAssertTrue(item1.status.isGenerating)

        let dummyURL = URL(fileURLWithPath: "/tmp/test.mp3")
        item1.status = .ready(fileURL: dummyURL, duration: 30.0)
        XCTAssertTrue(item1.status.isReady)

        // Test Queue Array Reordering
        var queue = [item1, item2, item3]
        XCTAssertEqual(queue.map(\.prompt), ["Track 1", "Track 2", "Track 3"])

        // Swap / move
        queue.swapAt(0, 1)
        XCTAssertEqual(queue.map(\.prompt), ["Track 2", "Track 1", "Track 3"])

        // Remove item
        queue.remove(at: 1)
        XCTAssertEqual(queue.map(\.prompt), ["Track 2", "Track 3"])
    }

    func testAudioFormatDetectorMagicBytes() {
        // 1. ID3 header (MP3 with C2PA / metadata)
        let id3Data = Data([0x49, 0x44, 0x33, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: id3Data), .mp3)
        XCTAssertEqual(AudioFormatDetector.preferredExtension(for: id3Data), "mp3")

        // 2. MPEG frame sync (Raw MP3 stream: 0xFF 0xFB)
        let mpegData = Data([0xFF, 0xFB, 0x90, 0x64, 0x00, 0x00, 0x00, 0x00])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: mpegData), .mp3)

        // 3. RIFF WAVE (Standard uncompressed WAV)
        let riffWaveData = Data([
            0x52, 0x49, 0x46, 0x46, // RIFF
            0x24, 0x08, 0x00, 0x00, // Size
            0x57, 0x41, 0x56, 0x45  // WAVE
        ])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: riffWaveData), .wav)
        XCTAssertEqual(AudioFormatDetector.preferredExtension(for: riffWaveData), "wav")

        // 4. FLAC
        let flacData = Data([0x66, 0x4C, 0x61, 0x43, 0x00, 0x00, 0x00, 0x22])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: flacData), .flac)

        // 5. M4A (ISO Base Media)
        let m4aData = Data([0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70, 0x4D, 0x34, 0x41, 0x20])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: m4aData), .m4a)

        // 6. Unknown / Empty
        let emptyData = Data([0x00, 0x01])
        XCTAssertEqual(AudioFormatDetector.detectFormat(from: emptyData), .unknown)
        XCTAssertEqual(AudioFormatDetector.preferredExtension(for: emptyData), "mp3")
    }

    func testGeminiFallbackSuggestions() {
        let engine = GeminiSuggestionEngine()
        let suggestions = engine.fallbackSuggestions(for: "Chill lo-fi beats")

        XCTAssertFalse(suggestions.similar.isEmpty)
        XCTAssertFalse(suggestions.fun.isEmpty)
        XCTAssertFalse(suggestions.wild.isEmpty)
        XCTAssertTrue(suggestions.similar.contains("Chill lo-fi beats"))
    }

    func testMCPServerStatusEnum() {
        let info = MCPServerInfo(name: "Lyria", version: "3.18.0")
        let tool = MCPTool(name: "lyria_generate_music", description: "Generate music")

        let status1 = MCPServerStatus.connected(serverInfo: info, tools: [tool])
        let status2 = MCPServerStatus.connected(serverInfo: info, tools: [tool])
        let status3 = MCPServerStatus.disconnected

        XCTAssertEqual(status1, status2)
        XCTAssertNotEqual(status1, status3)
    }

    func testAppSettingsDefaults() {
        let settings = AppSettings.shared
        XCTAssertFalse(settings.effectiveMcpBinaryPath.isEmpty)
        XCTAssertEqual(AppSettings.availableLyriaModels, ["lyria-3-clip-preview", "lyria-3-pro-preview"])
        XCTAssertEqual(AppSettings.availableGeminiModels, ["gemini-3.7-flash", "gemini-3.5-flash-lite"])
        XCTAssertTrue(AppSettings.availableGeminiModels.contains("gemini-3.7-flash"))
        XCTAssertTrue(AppSettings.availableGeminiModels.contains("gemini-3.5-flash-lite"))
        XCTAssertFalse(AppSettings.availableGeminiModels.contains("gemini-2.5-flash"))
        XCTAssertFalse(AppSettings.availableGeminiModels.contains("gemini-2.0-flash"))
    }

    @MainActor
    func testAudioEngine32BarSpectrumInitializationAndRestingBaseline() {
        let engine = AudioEngine()
        XCTAssertEqual(AudioEngine.barCount, 32)
        XCTAssertEqual(engine.powerLevels.count, 32)
        for level in engine.powerLevels {
            XCTAssertEqual(level, 0.04, accuracy: 0.001)
        }

        // Test Pause and Stop reset to resting baseline
        engine.pause()
        XCTAssertEqual(engine.powerLevels.count, 32)
        for level in engine.powerLevels {
            XCTAssertEqual(level, 0.04, accuracy: 0.001)
        }

        engine.stop()
        XCTAssertEqual(engine.powerLevels.count, 32)
        for level in engine.powerLevels {
            XCTAssertEqual(level, 0.04, accuracy: 0.001)
        }
    }

    @MainActor
    func testWaveformVisualizerViewInitialization() {
        let levels = Array(repeating: Float(0.04), count: 32)
        let visualizer = WaveformVisualizerView(powerLevels: levels, isPlaying: false)
        XCTAssertEqual(visualizer.powerLevels.count, 32)
        XCTAssertFalse(visualizer.isPlaying)
    }

    @MainActor
    func testWaveformVisualizerSafeBoundsHandling() {
        // Empty array
        let emptyVisualizer = WaveformVisualizerView(powerLevels: [], isPlaying: true)
        XCTAssertEqual(emptyVisualizer.powerLevels.count, 0)
        XCTAssertTrue(emptyVisualizer.isPlaying)

        // Non-standard count array (e.g. 16 or 64)
        let customVisualizer = WaveformVisualizerView(powerLevels: Array(repeating: Float(0.5), count: 16), isPlaying: true)
        XCTAssertEqual(customVisualizer.powerLevels.count, 16)
        XCTAssertTrue(customVisualizer.isPlaying)
    }

    @MainActor
    func testAudioEngineVolumeAndLoopProperties() {
        let engine = AudioEngine()
        engine.volume = 0.5
        XCTAssertEqual(engine.volume, 0.5, accuracy: 0.001)

        engine.isLooping = true
        XCTAssertTrue(engine.isLooping)

        engine.isLooping = false
        XCTAssertFalse(engine.isLooping)
    }

    @MainActor
    func testAudioEngineSeekBounds() {
        let engine = AudioEngine()
        // Seeking with no loaded player should not crash
        engine.seek(to: 10.0)
        XCTAssertEqual(engine.currentTime, 0)

        // Seeking with NaN should safely no-op
        engine.seek(to: Double.nan)
        XCTAssertEqual(engine.currentTime, 0)

        // Seeking with negative value
        engine.seek(to: -5.0)
        XCTAssertEqual(engine.currentTime, 0)
    }

    @MainActor
    func testAudioEngineTogglePlayPauseWhenEmpty() {
        let engine = AudioEngine()
        // When no track is loaded, togglePlayPause should safely no-op
        engine.togglePlayPause()
        XCTAssertFalse(engine.isPlaying)
        XCTAssertEqual(engine.powerLevels.count, 32)
    }

    @MainActor
    func testPlaybackCoordinatorQueueManipulation() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()
        XCTAssertEqual(coordinator.queue.count, 0)

        coordinator.addToQueue(prompt: "Queue Item 1", origin: "Similar")
        coordinator.addToQueue(prompt: "Queue Item 2", origin: "Fun")
        coordinator.addToQueue(prompt: "Queue Item 3", origin: "Wild")
        XCTAssertEqual(coordinator.queue.count, 3)
        XCTAssertEqual(coordinator.queue[0].prompt, "Queue Item 1")
        XCTAssertEqual(coordinator.queue[1].prompt, "Queue Item 2")
        XCTAssertEqual(coordinator.queue[2].prompt, "Queue Item 3")

        // Test playNext insert at index 0
        coordinator.addToQueue(prompt: "Urgent Item", origin: "Manual", playNext: true)
        XCTAssertEqual(coordinator.queue.count, 4)
        XCTAssertEqual(coordinator.queue[0].prompt, "Urgent Item")

        // Test Move Up / Down
        let idToMove = coordinator.queue[2].id
        coordinator.moveQueueItemUp(id: idToMove)
        XCTAssertEqual(coordinator.queue[1].id, idToMove)

        coordinator.moveQueueItemDown(id: idToMove)
        XCTAssertEqual(coordinator.queue[2].id, idToMove)

        // Test Move with IndexSet
        coordinator.moveQueueItem(from: IndexSet(integer: 0), to: 3)
        XCTAssertEqual(coordinator.queue.count, 4)

        // Test Remove
        coordinator.removeFromQueue(id: idToMove)
        XCTAssertEqual(coordinator.queue.count, 3)

        // Test Clear
        coordinator.clearQueue()
        XCTAssertEqual(coordinator.queue.count, 0)
    }

    func testSuggestionTypeIconsAndProperties() {
        XCTAssertEqual(SuggestionType.similar.iconName, "waveform.badge.magnifyingglass")
        XCTAssertEqual(SuggestionType.fun.iconName, "sparkles")
        XCTAssertEqual(SuggestionType.wild.iconName, "flame.fill")

        XCTAssertEqual(SuggestionType.similar.subtitle, "Vibe continuation")
        XCTAssertEqual(SuggestionType.fun.subtitle, "Playful mutation")
        XCTAssertEqual(SuggestionType.wild.subtitle, "Genre-bending shift")
    }

    func testQueueItemStatusEnumProperties() {
        let queued = QueueItemStatus.queued
        XCTAssertFalse(queued.isReady)
        XCTAssertFalse(queued.isGenerating)

        let generating = QueueItemStatus.generating
        XCTAssertFalse(generating.isReady)
        XCTAssertTrue(generating.isGenerating)

        let ready = QueueItemStatus.ready(fileURL: URL(fileURLWithPath: "/tmp/sample.mp3"), duration: 30.0)
        XCTAssertTrue(ready.isReady)
        XCTAssertFalse(ready.isGenerating)

        let failed = QueueItemStatus.failed("Network error")
        XCTAssertFalse(failed.isReady)
        XCTAssertFalse(failed.isGenerating)
    }

    func testPersistenceStoreURLConstruction() {
        let store = PersistenceStore.shared
        let track = Track(
            prompt: "Test Persistence",
            modelId: "lyria-3-clip-preview",
            audioFileName: "sample_track.mp3"
        )
        let url = store.audioFileURL(for: track)
        XCTAssertEqual(url.lastPathComponent, "sample_track.mp3")
        XCTAssertTrue(url.path.contains("LyriaFlow/Tracks"))
    }

    func testMovementSuiteCreationAndCodable() throws {
        let suite = MovementSuite(
            movement1: "Movement I (Atmospheric Build): Ethereal ambient pads",
            movement2: "Movement II (Deep Groove): Driving bass and syncopated beat",
            movement3: "Movement III (Climax/Outro): Epic orchestral synth crescendo"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(suite)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(MovementSuite.self, from: data)

        XCTAssertEqual(decoded.movement1, suite.movement1)
        XCTAssertEqual(decoded.movement2, suite.movement2)
        XCTAssertEqual(decoded.movement3, suite.movement3)
    }

    func testGeminiFallbackMovementSuite() {
        let engine = GeminiSuggestionEngine()
        let suite = engine.fallbackMovementSuite(for: "Cyberpunk Synthwave")

        XCTAssertTrue(suite.movement1.contains("Movement I"))
        XCTAssertTrue(suite.movement1.contains("Atmospheric Build"))
        XCTAssertTrue(suite.movement1.contains("Cyberpunk Synthwave"))

        XCTAssertTrue(suite.movement2.contains("Movement II"))
        XCTAssertTrue(suite.movement2.contains("Deep Groove"))
        XCTAssertTrue(suite.movement2.contains("Cyberpunk Synthwave"))

        XCTAssertTrue(suite.movement3.contains("Movement III"))
        XCTAssertTrue(suite.movement3.contains("Climax/Outro"))
        XCTAssertTrue(suite.movement3.contains("Cyberpunk Synthwave"))
    }

    @MainActor
    func testQueueMovementSuite() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()
        XCTAssertEqual(coordinator.queue.count, 0)

        coordinator.queueMovementSuite(for: "Lo-Fi Lounge", origin: "Fun Twist")
        XCTAssertEqual(coordinator.queue.count, 3)

        XCTAssertEqual(coordinator.queue[0].origin, "Fun Twist [1/3 Build]")
        XCTAssertTrue(coordinator.queue[0].prompt.contains("Movement I"))
        XCTAssertNotNil(coordinator.queue[0].seed)

        XCTAssertEqual(coordinator.queue[1].origin, "Fun Twist [2/3 Groove]")
        XCTAssertTrue(coordinator.queue[1].prompt.contains("Movement II"))
        XCTAssertNotNil(coordinator.queue[1].seed)

        XCTAssertEqual(coordinator.queue[2].origin, "Fun Twist [3/3 Climax]")
        XCTAssertTrue(coordinator.queue[2].prompt.contains("Movement III"))
        XCTAssertNotNil(coordinator.queue[2].seed)

        coordinator.clearQueue()
    }

    @MainActor
    func testAutoPlaySuiteGeneration() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()
        coordinator.settings.autoPlayEnabled = true

        let suggestions = GeminiSuggestions(
            similar: "Smooth deep house vibe",
            fun: "Funky disco groove with slap bass",
            wild: "Dark cinematic cyber glitch"
        )

        coordinator.scheduleAutoPlaySuite(suggestions: suggestions)

        XCTAssertEqual(coordinator.queue.count, 3)
        XCTAssertTrue(coordinator.queue[0].origin?.contains("Auto-Play:") == true)
        XCTAssertTrue(coordinator.queue[0].origin?.contains("[1/3 Build]") == true)
        XCTAssertTrue(coordinator.queue[1].origin?.contains("[2/3 Groove]") == true)
        XCTAssertTrue(coordinator.queue[2].origin?.contains("[3/3 Climax]") == true)

        coordinator.clearQueue()
    }

    @MainActor
    func testTrackMetadataPersistenceAndInspection() {
        let coordinator = PlaybackCoordinator()
        let suggestions = GeminiSuggestions(
            similar: "Ambient chord progression",
            fun: "Upbeat tropical bounce",
            wild: "Industrial techno frenzy"
        )

        let track = Track(
            prompt: "Sunset lo-fi chill hop with warm rhodes keys",
            modelId: "lyria-3-pro-preview",
            seed: 987654321,
            createdAt: Date(),
            duration: 32.0,
            audioFileName: "lyria_test_sample.mp3",
            suggestions: suggestions,
            isFavorite: true,
            status: .ready
        )

        XCTAssertEqual(track.prompt, "Sunset lo-fi chill hop with warm rhodes keys")
        XCTAssertEqual(track.modelId, "lyria-3-pro-preview")
        XCTAssertEqual(track.seed, 987654321)
        XCTAssertEqual(track.duration, 32.0)
        XCTAssertEqual(track.suggestions?.similar, "Ambient chord progression")

        coordinator.inspectingTrack = track
        XCTAssertEqual(coordinator.inspectingTrack?.id, track.id)
        XCTAssertEqual(coordinator.inspectingTrack?.seed, 987654321)

        coordinator.inspectingTrack = nil
        XCTAssertNil(coordinator.inspectingTrack)
    }

    func testQueuedTrackSeedInitialization() {
        let trackWithSeed = QueuedTrack(prompt: "Custom Seed Track", seed: 424242)
        XCTAssertEqual(trackWithSeed.seed, 424242)

        let trackWithRandomSeed = QueuedTrack(prompt: "Random Seed Track")
        XCTAssertNotNil(trackWithRandomSeed.seed)
    }

    @MainActor
    func testTrackInspectorViewInstantiation() {
        let coordinator = PlaybackCoordinator()
        let track = Track(
            prompt: "Test inspector instantiation",
            modelId: "lyria-3-clip-preview",
            seed: 112233,
            duration: 30.0,
            audioFileName: "test.mp3"
        )
        let inspectorView = TrackInspectorView(track: track, coordinator: coordinator)
        XCTAssertEqual(inspectorView.track.id, track.id)
    }

    func testGeminiGenerateMovementSuiteEmptyApiKeyFallback() async {
        let engine = GeminiSuggestionEngine()
        let suite = await engine.generateMovementSuite(vibePrompt: "Tokyo Night Jazz", apiKey: "   ")
        XCTAssertTrue(suite.movement1.contains("Movement I"))
        XCTAssertTrue(suite.movement1.contains("Atmospheric Build"))
        XCTAssertTrue(suite.movement1.contains("Tokyo Night Jazz"))

        XCTAssertTrue(suite.movement2.contains("Movement II"))
        XCTAssertTrue(suite.movement2.contains("Deep Groove"))
        XCTAssertTrue(suite.movement2.contains("Tokyo Night Jazz"))

        XCTAssertTrue(suite.movement3.contains("Movement III"))
        XCTAssertTrue(suite.movement3.contains("Climax/Outro"))
        XCTAssertTrue(suite.movement3.contains("Tokyo Night Jazz"))
    }

    @MainActor
    func testAutoPlaySuiteGenerationWithNilSuggestions() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()
        coordinator.settings.autoPlayEnabled = true
        coordinator.currentTrack = Track(prompt: "Melodic Techno Base", audioFileName: "base.mp3")

        coordinator.scheduleAutoPlaySuite(suggestions: nil)

        XCTAssertEqual(coordinator.queue.count, 3)
        XCTAssertEqual(coordinator.queue[0].origin, "Auto-Play [1/3 Build]")
        XCTAssertTrue(coordinator.queue[0].prompt.contains("Melodic Techno Base"))
        XCTAssertEqual(coordinator.queue[1].origin, "Auto-Play [2/3 Groove]")
        XCTAssertTrue(coordinator.queue[1].prompt.contains("Melodic Techno Base"))
        XCTAssertEqual(coordinator.queue[2].origin, "Auto-Play [3/3 Climax]")
        XCTAssertTrue(coordinator.queue[2].prompt.contains("Melodic Techno Base"))

        coordinator.clearQueue()
    }

    @MainActor
    func testTrackInspectorLiveFavoriteReactivity() {
        let coordinator = PlaybackCoordinator()
        let track = Track(
            prompt: "Live Favorite Test",
            audioFileName: "fav.mp3",
            isFavorite: false
        )
        coordinator.tracks = [track]
        coordinator.currentTrack = track

        coordinator.inspectingTrack = track
        XCTAssertFalse(coordinator.tracks[0].isFavorite)

        coordinator.toggleFavorite(for: track)
        XCTAssertTrue(coordinator.tracks[0].isFavorite)
        XCTAssertTrue(coordinator.currentTrack?.isFavorite == true)

        coordinator.inspectingTrack = nil
    }

    @MainActor
    func testSuggestionCardQueueMatchingSingleAndSuite() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()

        let suggestions = GeminiSuggestions(
            similar: "Ambient Chill",
            fun: "Funky Electro",
            wild: "Dark Cyber"
        )

        // Enqueue single item for similar
        coordinator.addToQueue(prompt: suggestions.similar, origin: SuggestionType.similar.rawValue)
        let similarIdx = coordinator.queue.firstIndex(where: {
            $0.prompt == suggestions.similar || $0.origin?.contains(SuggestionType.similar.rawValue) == true
        })
        XCTAssertEqual(similarIdx, 0)

        // Enqueue 3x movement suite for fun
        coordinator.queueMovementSuite(for: suggestions.fun, origin: SuggestionType.fun.rawValue)
        let funIdx = coordinator.queue.firstIndex(where: {
            $0.prompt == suggestions.fun || $0.origin?.contains(SuggestionType.fun.rawValue) == true
        })
        XCTAssertEqual(funIdx, 1)

        // Wild should not be queued yet
        let wildIdx = coordinator.queue.firstIndex(where: {
            $0.prompt == suggestions.wild || $0.origin?.contains(SuggestionType.wild.rawValue) == true
        })
        XCTAssertNil(wildIdx)

        coordinator.clearQueue()
    }

    @MainActor
    func testPlaybackCoordinatorEmptyPromptNoOps() {
        let coordinator = PlaybackCoordinator()
        coordinator.clearQueue()

        coordinator.addToQueue(prompt: "   ")
        XCTAssertEqual(coordinator.queue.count, 0)

        coordinator.addToQueue(prompt: "")
        XCTAssertEqual(coordinator.queue.count, 0)

        coordinator.queueMovementSuite(for: "   ", origin: "Test")
        XCTAssertEqual(coordinator.queue.count, 0)
    }

    @MainActor
    func testTrackDeleteStopsPlayingTrack() {
        let coordinator = PlaybackCoordinator()
        let track = Track(prompt: "Playing Track to Delete", audioFileName: "to_delete.mp3")
        coordinator.tracks = [track]
        coordinator.currentTrack = track
        coordinator.inspectingTrack = track

        coordinator.deleteTrack(track)
        XCTAssertNil(coordinator.currentTrack)
        XCTAssertNil(coordinator.inspectingTrack)
        XCTAssertFalse(coordinator.tracks.contains(where: { $0.id == track.id }))
    }

    func testPersistenceRoundTripWithRichMetadata() throws {
        let originalSuggestions = GeminiSuggestions(
            similar: "Smooth lo-fi chillhop with vinyl crackle",
            fun: "Upbeat future bass drop",
            wild: "Dark cinematic synthwave pulse"
        )
        let track = Track(
            prompt: "Cyberpunk rooftop rain ambience with synth pads",
            modelId: "lyria-3-pro-preview",
            seed: 778899,
            createdAt: Date(),
            duration: 45.2,
            audioFileName: "lyria_test_roundtrip.mp3",
            suggestions: originalSuggestions,
            isFavorite: true,
            status: .ready
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode([track])

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedTracks = try decoder.decode([Track].self, from: encodedData)

        XCTAssertEqual(decodedTracks.count, 1)
        let decoded = decodedTracks[0]
        XCTAssertEqual(decoded.id, track.id)
        XCTAssertEqual(decoded.prompt, track.prompt)
        XCTAssertEqual(decoded.modelId, "lyria-3-pro-preview")
        XCTAssertEqual(decoded.seed, 778899)
        XCTAssertEqual(decoded.duration, 45.2, accuracy: 0.001)
        XCTAssertEqual(decoded.audioFileName, "lyria_test_roundtrip.mp3")
        XCTAssertEqual(decoded.isFavorite, true)
        XCTAssertEqual(decoded.status, .ready)
        XCTAssertEqual(decoded.suggestions, originalSuggestions)
    }

    func testAppLoggerLoggingAndRetrieval() {
        let logger = AppLogger.shared
        logger.log("Test log entry for verification", category: "UNIT_TEST")
        logger.error("Test error entry", category: "UNIT_TEST")

        let logs = logger.getRecentLogs(maxLines: 20)
        XCTAssertTrue(logs.contains("Test log entry for verification"))
        XCTAssertTrue(logs.contains("Test error entry"))
        XCTAssertTrue(logs.contains("[UNIT_TEST]"))
    }

    func testEnvironmentLoaderDiscoveryAndFallback() {
        let loader = EnvironmentLoader.shared
        let env = loader.resolvedEnvironment()
        XCTAssertNotNil(env["PATH"])
        XCTAssertTrue(env["PATH"]?.contains("/usr/bin") == true)
        XCTAssertNotNil(env["HOME"])
    }
}
