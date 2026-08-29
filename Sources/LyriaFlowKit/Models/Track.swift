import Foundation

public struct GeminiSuggestions: Codable, Equatable, Sendable {
    public var similar: String
    public var fun: String
    public var wild: String

    public init(similar: String = "", fun: String = "", wild: String = "") {
        self.similar = similar
        self.fun = fun
        self.wild = wild
    }
}

public enum SuggestionType: String, CaseIterable, Identifiable, Codable, Sendable {
    case similar = "Similar"
    case fun = "Fun Twist"
    case wild = "Wildcard"

    public var id: String { rawValue }

    public var iconName: String {
        switch self {
        case .similar: return "waveform.badge.magnifyingglass"
        case .fun: return "sparkles"
        case .wild: return "flame.fill"
        }
    }

    public var subtitle: String {
        switch self {
        case .similar: return "Vibe continuation"
        case .fun: return "Playful mutation"
        case .wild: return "Genre-bending shift"
        }
    }
}

public enum TrackStatus: String, Codable, Sendable {
    case ready
    case generating
    case pregenerated
    case failed
}

public struct Track: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public var prompt: String
    public var modelId: String
    public var seed: UInt32?
    public var createdAt: Date
    public var duration: TimeInterval
    public var audioFileName: String
    public var suggestions: GeminiSuggestions?
    public var isFavorite: Bool
    public var status: TrackStatus

    public init(
        id: UUID = UUID(),
        prompt: String,
        modelId: String = "lyria-3-clip-preview",
        seed: UInt32? = nil,
        createdAt: Date = Date(),
        duration: TimeInterval = 0,
        audioFileName: String,
        suggestions: GeminiSuggestions? = nil,
        isFavorite: Bool = false,
        status: TrackStatus = .ready
    ) {
        self.id = id
        self.prompt = prompt
        self.modelId = modelId
        self.seed = seed
        self.createdAt = createdAt
        self.duration = duration
        self.audioFileName = audioFileName
        self.suggestions = suggestions
        self.isFavorite = isFavorite
        self.status = status
    }
}

public enum QueueItemStatus: Equatable, Sendable {
    case queued
    case generating
    case ready(fileURL: URL, duration: TimeInterval)
    case failed(String)

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }

    public var isGenerating: Bool {
        if case .generating = self { return true }
        return false
    }
}

public struct QueuedTrack: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var prompt: String
    public var modelId: String
    public var seed: UInt32?
    public var origin: String?
    public var audioFileName: String
    public var status: QueueItemStatus
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        prompt: String,
        modelId: String = "lyria-3-clip-preview",
        seed: UInt32? = nil,
        origin: String? = nil,
        audioFileName: String? = nil,
        status: QueueItemStatus = .queued,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.prompt = prompt
        self.modelId = modelId
        self.seed = seed ?? UInt32.random(in: 100_000...999_999_999)
        self.origin = origin
        self.audioFileName = audioFileName ?? "lyria_q_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.prefix(6)).mp3"
        self.status = status
        self.createdAt = createdAt
    }
}
