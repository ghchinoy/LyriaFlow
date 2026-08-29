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
}
