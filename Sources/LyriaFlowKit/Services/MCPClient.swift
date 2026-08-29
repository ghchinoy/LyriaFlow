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

    public init() {}

    public func isConnected() -> Bool {
        return isRunning && process?.isRunning == true
    }

    public func start(binaryPath: String) throws {
        if isRunning {
            stop()
        }

        guard FileManager.default.isExecutableFile(atPath: binaryPath) else {
            let err = "Binary at '\(binaryPath)' is not executable or does not exist."
            AppLogger.shared.error(err, category: "MCP")
            throw NSError(domain: "MCPClient", code: 1, userInfo: [NSLocalizedDescriptionKey: err])
        }

        AppLogger.shared.log("Launching mcp-lyria binary at: \(binaryPath)", category: "MCP")

        let p = Process()
        p.executableURL = URL(fileURLWithPath: binaryPath)
        p.arguments = ["-transport", "stdio"]
        
        // Pass enriched environment containing PATH, GOOGLE_APPLICATION_CREDENTIALS, etc.
        p.environment = EnvironmentLoader.shared.resolvedEnvironment()

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
                let trimmed = msg.trimmingCharacters(in: .whitespacesAndNewlines)
                AppLogger.shared.log(trimmed, category: "MCP-STDERR")
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

        p.terminationHandler = { [weak self] proc in
            Task { [weak self] in
                await self?.handleProcessTerminated(exitCode: proc.terminationStatus)
            }
        }

        try p.run()
        self.isRunning = true
        AppLogger.shared.log("mcp-lyria-go process started (PID: \(p.processIdentifier))", category: "MCP")
    }

    private func handleProcessTerminated(exitCode: Int32) {
        AppLogger.shared.warning("mcp-lyria-go process exited with code \(exitCode)", category: "MCP")
        isRunning = false
        for (_, continuation) in pendingRequests {
            continuation.resume(throwing: NSError(domain: "MCPClient", code: -1, userInfo: [NSLocalizedDescriptionKey: "mcp-lyria-go exited unexpectedly (code \(exitCode))."]))
        }
        pendingRequests.removeAll()
    }

    public func stop() {
        isRunning = false
        stdoutPipe?.fileHandleForReading.readabilityHandler = nil
        stderrPipe?.fileHandleForReading.readabilityHandler = nil
        if let p = process, p.isRunning {
            p.terminationHandler = nil
            p.terminate()
            AppLogger.shared.log("mcp-lyria-go process terminated", category: "MCP")
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
        buffer.append(data)
        var linesToProcess: [String] = []

        while let newlineRange = buffer.range(of: Data([0x0A])) {
            let lineData = buffer.subdata(in: 0..<newlineRange.lowerBound)
            buffer.removeSubrange(0..<newlineRange.upperBound)
            if let str = String(data: lineData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !str.isEmpty {
                linesToProcess.append(str)
            }
        }

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

    public func sendRequest(method: String, params: [String: Any], timeoutSeconds: TimeInterval = 25.0) async throws -> [String: Any] {
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

        // Schedule timeout watchdog
        Task { [weak self, reqId] in
            try? await Task.sleep(nanoseconds: UInt64(timeoutSeconds * 1_000_000_000))
            await self?.handleTimeout(reqId: reqId, method: method, timeoutSeconds: timeoutSeconds)
        }

        return try await withCheckedThrowingContinuation { continuation in
            self.pendingRequests[reqId] = continuation
            stdin.write(data)
            stdin.write("\n".data(using: .utf8)!)
        }
    }

    private func handleTimeout(reqId: Int, method: String, timeoutSeconds: TimeInterval) {
        if let continuation = pendingRequests.removeValue(forKey: reqId) {
            let err = "MCP request '\(method)' (ID: \(reqId)) timed out after \(Int(timeoutSeconds))s"
            AppLogger.shared.error(err, category: "MCP")
            continuation.resume(throwing: NSError(domain: "MCPClient", code: 408, userInfo: [NSLocalizedDescriptionKey: err]))
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

        // 1. Initialize with 12s timeout
        let initResponse = try await sendRequest(
            method: "initialize",
            params: [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": [
                    "name": "LyriaFlow",
                    "version": "1.0.0"
                ]
            ],
            timeoutSeconds: 12.0
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

        // 3. List tools with 12s timeout
        let toolsResponse = try await sendRequest(method: "tools/list", params: [:], timeoutSeconds: 12.0)
        var toolsList: [MCPTool] = []

        if let result = toolsResponse["result"] as? [String: Any],
           let tools = result["tools"] as? [[String: Any]] {
            for t in tools {
                let name = t["name"] as? String ?? ""
                let desc = t["description"] as? String
                toolsList.append(MCPTool(name: name, description: desc))
            }
        }

        AppLogger.shared.log("Lyria MCP initialized: \(serverInfo.name) v\(serverInfo.version ?? ""), tools: \(toolsList.map(\.name))", category: "MCP")
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

        AppLogger.shared.log("Calling lyria_generate_music with prompt: \"\(prompt.prefix(60))...\", model: \(modelId), file: \(fileName)", category: "MCP")

        // Allow up to 120 seconds for music synthesis
        let response = try await sendRequest(
            method: "tools/call",
            params: [
                "name": "lyria_generate_music",
                "arguments": args
            ],
            timeoutSeconds: 120.0
        )

        if let errorObj = response["error"] as? [String: Any] {
            let msg = errorObj["message"] as? String ?? "Unknown MCP Error"
            AppLogger.shared.error("MCP RPC error: \(msg)", category: "MCP")
            throw NSError(domain: "MCPClient", code: 3, userInfo: [NSLocalizedDescriptionKey: msg])
        }

        guard let result = response["result"] as? [String: Any] else {
            AppLogger.shared.error("Invalid tool response format: \(response)", category: "MCP")
            throw NSError(domain: "MCPClient", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid tool response format"])
        }

        if let isError = result["isError"] as? Bool, isError {
            var errorDetails = "Tool reported error"
            if let content = result["content"] as? [[String: Any]],
               let first = content.first,
               let text = first["text"] as? String {
                errorDetails = text
            }
            AppLogger.shared.error("Lyria generation failed: \(errorDetails)", category: "MCP")
            throw NSError(domain: "MCPClient", code: 5, userInfo: [NSLocalizedDescriptionKey: errorDetails])
        }

        var message = "Music generated successfully"
        if let content = result["content"] as? [[String: Any]],
           let first = content.first,
           let text = first["text"] as? String {
            message = text
        }
        AppLogger.shared.log("Tool response: \(message)", category: "MCP")

        // Robustly locate generated file on disk
        let fm = FileManager.default
        let expectedURL = localDir.appendingPathComponent(fileName)
        let baseName = (fileName as NSString).deletingPathExtension

        var candidateURLs: [URL] = [
            expectedURL,
            localDir.appendingPathComponent("\(baseName).wav"),
            localDir.appendingPathComponent("\(baseName).mp3")
        ]

        if let range = message.range(of: "Successfully saved audio locally to ") {
            let pathPart = String(message[range.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: ". \n\r\t"))
            if !pathPart.isEmpty {
                candidateURLs.insert(URL(fileURLWithPath: pathPart), at: 0)
            }
        }

        for candidate in candidateURLs {
            if fm.fileExists(atPath: candidate.path) {
                let detected = AudioFormatDetector.detectFormat(for: candidate)
                AppLogger.shared.log("Found audio file at \(candidate.path), detected format: \(detected.displayName)", category: "AUDIO")

                if detected == .mp3 && candidate.pathExtension.lowercased() == "wav" && fileName.hasSuffix(".mp3") {
                    let targetMP3URL = localDir.appendingPathComponent(fileName)
                    try? fm.removeItem(at: targetMP3URL)
                    do {
                        try fm.moveItem(at: candidate, to: targetMP3URL)
                        AppLogger.shared.log("Renamed \(candidate.lastPathComponent) -> \(targetMP3URL.lastPathComponent) (native MP3 container)", category: "AUDIO")
                        return (targetMP3URL, message)
                    } catch {
                        AppLogger.shared.warning("Could not rename to .mp3, using \(candidate.path): \(error)", category: "AUDIO")
                        return (candidate, message)
                    }
                }
                return (candidate, message)
            }
        }

        let dirContents = (try? fm.contentsOfDirectory(atPath: localDir.path)) ?? []
        let errorMsg = "Audio file not found at \(expectedURL.path) after generation. Directory contents: \(dirContents.prefix(10))"
        AppLogger.shared.error(errorMsg, category: "MCP")
        throw NSError(domain: "MCPClient", code: 6, userInfo: [NSLocalizedDescriptionKey: errorMsg])
    }
}
