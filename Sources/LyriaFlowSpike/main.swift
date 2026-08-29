import Foundation

print("==========================================")
print("🎵 LyriaFlow MCP Verification Spike")
print("==========================================")

// 1. Locate mcp-lyria-go binary
let possiblePaths = [
    "/Users/ghchinoy/go/bin/mcp-lyria-go",
    "\(FileManager.default.homeDirectoryForCurrentUser.path)/go/bin/mcp-lyria-go",
    "/usr/local/bin/mcp-lyria-go",
    "\(FileManager.default.homeDirectoryForCurrentUser.path)/.local/bin/mcp-lyria-go"
]

guard let binaryPath = possiblePaths.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
    print("❌ Error: mcp-lyria-go executable not found in candidate paths: \(possiblePaths)")
    exit(1)
}

print("✅ Found Lyria MCP Binary: \(binaryPath)")

// 2. Prepare environment and working directory
var env = ProcessInfo.processInfo.environment
if env["GEMINI_API_KEY"] == nil {
    print("⚠️ Notice: GEMINI_API_KEY is not set in current process environment.")
} else {
    print("✅ GEMINI_API_KEY detected in environment.")
}
if let project = env["GOOGLE_CLOUD_PROJECT"] {
    print("✅ GOOGLE_CLOUD_PROJECT: \(project)")
}

let tracksDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Music")
    .appendingPathComponent("LyriaFlow")
    .appendingPathComponent("Tracks")

try? FileManager.default.createDirectory(at: tracksDir, withIntermediateDirectories: true)
print("📁 Output directory ready: \(tracksDir.path)")

// 3. Launch Process
let process = Process()
process.executableURL = URL(fileURLWithPath: binaryPath)
process.arguments = ["-transport", "stdio"]
process.environment = env

let stdinPipe = Pipe()
let stdoutPipe = Pipe()
let stderrPipe = Pipe()

process.standardInput = stdinPipe
process.standardOutput = stdoutPipe
process.standardError = stderrPipe

final class StdioLineReader: @unchecked Sendable {
    private let stream: AsyncStream<String>
    private var continuation: AsyncStream<String>.Continuation?
    private var buffer = Data()
    private let lock = NSLock()
    private var iterator: AsyncStream<String>.AsyncIterator

    init(handle: FileHandle) {
        var cont: AsyncStream<String>.Continuation?
        let s = AsyncStream<String> { c in
            cont = c
        }
        self.stream = s
        self.continuation = cont
        self.iterator = s.makeAsyncIterator()

        handle.readabilityHandler = { [weak self] h in
            guard let self = self else { return }
            let data = h.availableData
            if data.isEmpty {
                self.continuation?.finish()
                return
            }
            self.lock.lock()
            self.buffer.append(data)
            while let newlineRange = self.buffer.range(of: Data([0x0A])) {
                let lineData = self.buffer.subdata(in: 0..<newlineRange.lowerBound)
                self.buffer.removeSubrange(0..<newlineRange.upperBound)
                if let lineStr = String(data: lineData, encoding: .utf8) {
                    self.continuation?.yield(lineStr)
                }
            }
            self.lock.unlock()
        }
    }

    func nextJSON() async throws -> [String: Any]? {
        while let line = await iterator.next() {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            guard let data = trimmed.data(using: .utf8) else { continue }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return json
            } else {
                print("  [raw stdout]: \(trimmed)")
            }
        }
        return nil
    }
}

do {
    try process.run()
    print("🚀 Launched mcp-lyria-go process (PID: \(process.processIdentifier))")
} catch {
    print("❌ Failed to start mcp-lyria-go process: \(error)")
    exit(1)
}

stderrPipe.fileHandleForReading.readabilityHandler = { h in
    let data = h.availableData
    if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
        print("  [mcp stderr] \(str.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
}

let reader = StdioLineReader(handle: stdoutPipe.fileHandleForReading)

func sendRPC(message: [String: Any]) throws {
    let data = try JSONSerialization.data(withJSONObject: message, options: [])
    stdinPipe.fileHandleForWriting.write(data)
    stdinPipe.fileHandleForWriting.write("\n".data(using: .utf8)!)
}

// Step 1: Initialize Handshake
print("\n--- Step 1: Sending 'initialize' ---")
let initRequest: [String: Any] = [
    "jsonrpc": "2.0",
    "id": 1,
    "method": "initialize",
    "params": [
        "protocolVersion": "2024-11-05",
        "capabilities": [:] as [String: Any],
        "clientInfo": [
            "name": "LyriaFlowSpike",
            "version": "1.0.0"
        ]
    ]
]
try sendRPC(message: initRequest)

if let initResponse = try await reader.nextJSON() {
    print("✅ Initialize Response:")
    if let result = initResponse["result"] as? [String: Any] {
        print("   Server Info: \(result["serverInfo"] ?? [:])")
        print("   Protocol Version: \(result["protocolVersion"] ?? "")")
    } else {
        print("   \(initResponse)")
    }
}

// Step 2: notifications/initialized
print("\n--- Step 2: Sending 'notifications/initialized' ---")
let initializedNotif: [String: Any] = [
    "jsonrpc": "2.0",
    "method": "notifications/initialized",
    "params": [:] as [String: Any]
]
try sendRPC(message: initializedNotif)
print("✅ Sent initialized notification")

// Step 3: tools/list
print("\n--- Step 3: Sending 'tools/list' ---")
let listToolsRequest: [String: Any] = [
    "jsonrpc": "2.0",
    "id": 2,
    "method": "tools/list",
    "params": [:] as [String: Any]
]
try sendRPC(message: listToolsRequest)

var foundLyriaTool = false
if let toolsResponse = try await reader.nextJSON() {
    print("✅ Tools List Response:")
    if let result = toolsResponse["result"] as? [String: Any],
       let tools = result["tools"] as? [[String: Any]] {
        for tool in tools {
            let name = tool["name"] as? String ?? "unknown"
            let desc = tool["description"] as? String ?? ""
            print("   🔧 Tool: \(name) - \(desc.prefix(60))...")
            if name == "lyria_generate_music" {
                foundLyriaTool = true
            }
        }
    } else {
        print("   \(toolsResponse)")
    }
}

guard foundLyriaTool else {
    print("❌ lyria_generate_music tool not found on server!")
    process.terminate()
    exit(1)
}

// Step 4: Test Music Generation
let testFileName = "spike_test_\(Int(Date().timeIntervalSince1970)).wav"
let testPrompt = "Warm lo-fi ambient electronic music with soft rhodes and lush analog synth pads"
print("\n--- Step 4: Calling 'lyria_generate_music' ---")
print("Prompt: \"\(testPrompt)\"")
print("Target File: \(tracksDir.path)/\(testFileName)")

let generateRequest: [String: Any] = [
    "jsonrpc": "2.0",
    "id": 3,
    "method": "tools/call",
    "params": [
        "name": "lyria_generate_music",
        "arguments": [
            "prompt": testPrompt,
            "local_path": tracksDir.path,
            "file_name": testFileName,
            "model_id": "lyria-3-clip-preview"
        ]
    ]
]
let startTime = Date()
try sendRPC(message: generateRequest)

if let genResponse = try await reader.nextJSON() {
    let duration = Date().timeIntervalSince(startTime)
    print("✅ Music Generation Response in \(String(format: "%.2f", duration))s:")
    if let result = genResponse["result"] as? [String: Any] {
        if let isError = result["isError"] as? Bool, isError {
            print("❌ Tool returned error: \(result)")
        } else if let content = result["content"] as? [[String: Any]] {
            for item in content {
                if let text = item["text"] as? String {
                    print("   Tool Output: \(text)")
                }
            }
        }
    } else if let error = genResponse["error"] as? [String: Any] {
        print("❌ RPC Error: \(error)")
    }
}

// Verify output file on disk
let expectedPath = tracksDir.appendingPathComponent(testFileName)
if FileManager.default.fileExists(atPath: expectedPath.path) {
    let attrs = try FileManager.default.attributesOfItem(atPath: expectedPath.path)
    let fileSize = attrs[.size] as? Int ?? 0
    print("🎉 Verification SUCCESS! File created at: \(expectedPath.path) (\(fileSize) bytes)")
} else {
    print("⚠️ Checking directory contents...")
    let contents = (try? FileManager.default.contentsOfDirectory(atPath: tracksDir.path)) ?? []
    print("   Directory contents: \(contents)")
}

// Shutdown clean
print("\n--- Cleaning up ---")
process.terminate()
print("✅ LyriaFlow Spike completed successfully!\n")
