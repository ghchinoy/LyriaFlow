import Foundation
import SwiftUI

public final class AppSettings: ObservableObject {
    @AppStorage("gemini_api_key") public var storedGeminiApiKey: String = ""
    @AppStorage("mcp_binary_path") public var customMcpBinaryPath: String = ""
    @AppStorage("default_model_id") public var defaultModelId: String = "lyria-3-clip-preview"
    @AppStorage("gemini_model") public var geminiModel: String = "gemini-3.7-flash"
    @AppStorage("auto_play_enabled") public var autoPlayEnabled: Bool = true
    @AppStorage("loop_enabled") public var loopEnabled: Bool = false
    @AppStorage("volume") public var volume: Double = 0.85

    public static let shared = AppSettings()

    public var effectiveGeminiApiKey: String {
        if !storedGeminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return storedGeminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let envKey = EnvironmentLoader.shared.value(for: "GEMINI_API_KEY"), !envKey.isEmpty {
            return envKey
        }
        return ""
    }

    public var geminiKeySourceDescription: String {
        if !storedGeminiApiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Using custom key saved in Settings."
        }
        if let envKey = EnvironmentLoader.shared.value(for: "GEMINI_API_KEY"), !envKey.isEmpty {
            return "Loaded from environment / shell (\(envKey.prefix(6))...)"
        }
        return "No API key configured. Offline musical variation templates will be used."
    }

    public var effectiveMcpBinaryPath: String {
        if !customMcpBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return customMcpBinaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let envBinary = EnvironmentLoader.shared.value(for: "MCP_LYRIA_BINARY"),
           FileManager.default.isExecutableFile(atPath: envBinary) {
            return envBinary
        }
        let possiblePaths = [
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/go/bin/mcp-lyria-go",
            "/Users/ghchinoy/go/bin/mcp-lyria-go",
            "/opt/homebrew/bin/mcp-lyria-go",
            "/usr/local/bin/mcp-lyria-go",
            "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/mcp-lyria-go"
        ]
        return possiblePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) ?? possiblePaths[0]
    }

    public var tracksDirectory: URL {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Music")
            .appendingPathComponent("LyriaFlow")
            .appendingPathComponent("Tracks")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static let availableLyriaModels = [
        "lyria-3-clip-preview",
        "lyria-3-pro-preview"
    ]

    public static let availableGeminiModels = [
        "gemini-3.7-flash",
        "gemini-3.5-flash-lite"
    ]
}
