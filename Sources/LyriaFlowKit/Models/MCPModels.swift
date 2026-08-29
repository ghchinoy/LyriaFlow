import Foundation

public struct MCPTool: Identifiable, Codable, Equatable, Sendable {
    public var id: String { name }
    public let name: String
    public let description: String?
    public let inputSchema: [String: AnyCodable]?

    public init(name: String, description: String?, inputSchema: [String: AnyCodable]? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    public static func == (lhs: MCPTool, rhs: MCPTool) -> Bool {
        return lhs.name == rhs.name && lhs.description == rhs.description
    }
}

public struct MCPServerInfo: Codable, Equatable, Sendable {
    public let name: String
    public let version: String?
}

public enum MCPServerStatus: Equatable, Sendable {
    case disconnected
    case connecting
    case connected(serverInfo: MCPServerInfo, tools: [MCPTool])
    case error(String)
}

public struct AnyCodable: Codable, Equatable, @unchecked Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        return String(describing: lhs.value) == String(describing: rhs.value)
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
        } else if let int = try? container.decode(Int.self) {
            value = int
        } else if let double = try? container.decode(Double.self) {
            value = double
        } else if let string = try? container.decode(String.self) {
            value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            value = array.map { $0.value }
        } else if let dict = try? container.decode([String: AnyCodable].self) {
            value = dict.mapValues { $0.value }
        } else {
            value = ""
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let val = value as? String {
            try container.encode(val)
        } else if let val = value as? Int {
            try container.encode(val)
        } else if let val = value as? Double {
            try container.encode(val)
        } else if let val = value as? Bool {
            try container.encode(val)
        } else if let val = value as? [String: Any] {
            let wrapped = val.mapValues { AnyCodable($0) }
            try container.encode(wrapped)
        } else if let val = value as? [Any] {
            let wrapped = val.map { AnyCodable($0) }
            try container.encode(wrapped)
        } else {
            try container.encodeNil()
        }
    }
}
