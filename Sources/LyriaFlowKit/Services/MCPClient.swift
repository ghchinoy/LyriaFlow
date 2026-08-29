import Foundation

public actor MCPClient {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var isRunning: Bool = false
    private var pendingRequests: [Int: CheckedContinuation<[String: Any], Error>] = [:]
    private var requestIdCounter: Int = 0
    private var buffer = Data()
    private let lock = NSLock()

    public init() {}

    public func isConnected() -> Bool {
        return isRunning && process?.isRunning == true
    }

    public func start(binaryPath: String) throws {
        if isRunning {
            stop()
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            throw NSError(domain: "MCPClient", code: 1, userInfo: [NSLocalizedDescriptionKey: "Binary at '\(binaryPath)' is not executable or does not exist."])
        }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["-transport", "stdio"]
        p.environment = ProcessInfo.processInfo.environment

        let sin = Pipe()
        let sout = Pipe()
        let serr = Pipe()

        p.standardInput = sin
        p.standardOutput = sout
        p.standardError = serr

        self.process = p
        self.stdinPipe = sin
        self.stdoutPipe = sout
        self.stderrPipe = serr

        // Log stderr for diagnostics
        serr.fileHandleForReading.readabilityHandler = { h in
            let data = h.availableData
            if !data.isEmpty, let msg = String(data: data, encoding: .utf8) {
                print("[mcp-lyria stderr] \(msg.trimmingCharacters(in: .whitespacesAndNewlines))")
            }
        }

        // Setup stdout line processing
        sout.fileHandleForReading.readabilityHandler = { [weak self] h in
            let data = h.availableData
            if data.isEmpty { return }
            guard let self = self else { return }
            Task {
                await self.handleStdoutData(data)
            }
        }

        try p.run()
        self.isRunning = true
    }

    public func stop() {
        isRunning = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminate()
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil

        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "Process stopped."]))
        }
        pendingRequests.removeAll()
    }

    private func handleStdoutData(_ data: Data) {
        lock.lock()
        buffer.append(data)
        var linesToProcess: [String] = []

        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            if let str = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                linesToProcess.append(str)
            }
        }
        lock.unlock()

        for line in linesToProcess {
            if let jsonData = line.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                if let reqId = json["id"] as? Int, let continuation = pendingRequests.removeValue(forKey: reqId) {
                    continuation.resume(returning: json)
                }
            }
        }
    }

    private func nextRequestId() -> Int {
        requestIdCounter += 1
        return requestIdCounter
    }

    public func sendRequest(method: String, params: [String: Any]) async throws -> [String: Any] {
        guard isRunning, let stdin = stdinPipe?.fileHandleForWriting else {
            throw NSError(domain: "MCPClient", code: 2, userInfo: [NSLocalizedDescriptionKey: "MCP Server is not running."])
        }

        let reqId = nextRequestId()
        let requestDict: [String: Any] = [
            "jsonrpc": "2.0",
            "id": reqId,
            "method": method,
            "params": params
        ]

        let data = try JSONSerialization.data(withJSONObject: requestDict, options: [])

        return try await withCheckedThrowingContinuation { continuation in
            pendingRequests[reqId] = continuation
            stdin.write(data)
            stdin.write("\n".data(using: .utf8)!)
        }
    }

    public func sendNotification(method: String, params: [String: Any] = [:]) throws {
        guard isRunning, let stdin = stdinPipe?.fileHandleForWriting else { return }
        let notifDict: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: notifDict, options: [])
        stdin.write(data)
        stdin.write("\n".data(using: .utf8)!)
    }

    public func initializeAndVerify(binaryPath: String) async throws -> (serverInfo: MCPServerInfo, tools: [MCPTool]) {
        try start(binaryPath: binaryPath)

        // 1. Initialize
        let initResponse = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "LyriaFlow",
                    "version": "1.0.0"
                ]
            ]
        )

        var serverInfo = MCPServerInfo(name: "Lyria", version: "unknown")
        if let result = initResponse["result"] as? [String: Any],
           let sInfo = result["serverInfo"] as? [String: Any] {
            serverInfo = MCPServerInfo(
                name: sInfo["name"] as? String ?? "Lyria",
                version: sInfo["version"] as? String
            )
        }

        // 2. Initialized notification
        try sendNotification(method: "notifications/initialized")

        // 3. List tools
        let toolsResponse = try await sendRequest(method: "tools/list", params: [:])
        var toolsList: [MCPTool] = []

        if let result = toolsResponse["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            for t in tools {
                let name = t["name"] as? String ?? ""
                let desc = t["description"] as? String
                toolsList.append(MCPTool(name: name, description: desc))
            }
        }

        return (serverInfo, toolsList)
    }

    public func generateMusic(
        prompt: String,
        modelId: String,
        localDir: URL,
        fileName: String,
        negativePrompt: String? = nil,
        seed: UInt32? = nil
    ) async throws -> (audioFileURL: URL, toolMessage: String) {
        var args: [String: Any] = [
            "prompt": prompt,
            "model_id": modelId,
            "local_path": localDir.path,
            "file_name": fileName
        ]
        if let neg = negativePrompt, !neg.isEmpty {
            args["negative_prompt"] = neg
        }
        if let s = seed {
            args["seed"] = s
        }

        let response = try await sendRequest(
            method: "tools/call",
            params: [
                "name": "lyria_generate_music",
                "arguments": args
            ]
        )

        if let errorObj = response["error"] as? [String: Any] {
            let msg = errorObj["message"] as? String ?? "Unknown MCP Error"
            throw NSError(domain: "MCPClient", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let result = response["result"] as? [String: Any] else {
            throw NSError(domain: "MCPClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid tool response format"])
        }

        if let isError = result["isError"] as? Bool, isError {
            var errorDetails = "Tool reported error"
            if let content = result["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                errorDetails = text
            }
            throw NSError(domain: "MCPClient", code: 5, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }

        var message = "Music generated successfully"
        if let content = result["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            message = text
        }

        let expectedURL = localDir.appendingPathComponent(fileName)
        return (expectedURL, message)
    }
}
