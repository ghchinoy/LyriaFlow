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
            audioFileName: "test_file.wav",
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
        XCTAssertEqual(decoded.audioFileName, "test_file.wav")
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

        item1.status = .generating
        XCTAssertTrue(item1.status.isGenerating)

        let dummyURL = URL(fileURLWithPath: "/tmp/test.wav")
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
        XCTAssertTrue(AppSettings.availableGeminiModels.contains("gemini-2.5-flash"))
        XCTAssertTrue(AppSettings.availableGeminiModels.contains("gemini-3.7-flash"))
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

        let ready = QueueItemStatus.ready(fileURL: URL(fileURLWithPath: "/tmp/sample.wav"), duration: 30.0)
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
            audioFileName: "sample_track.wav"
        )
        let url = store.audioFileURL(for: track)
        XCTAssertEqual(url.lastPathComponent, "sample_track.wav")
        XCTAssertTrue(url.path.contains("LyriaFlow/Tracks"))
    }
}
