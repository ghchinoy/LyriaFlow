import Foundation
import AppKit

/// Thread-safe logger for LyriaFlow that outputs to both standard output and a persistent rotating log file on disk.
public final class AppLogger: @unchecked Sendable {
    public static let shared = AppLogger()

    public let logFileURL: URL
    private let logDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()
    private let dateFormatter: ISO8601DateFormatter

    private init() {
        let libraryDir = fileManager.urls(for: .libraryDirectory, in: .userDomainMask).first!
        let logsDir = libraryDir.appendingPathComponent("Logs", isDirectory: true).appendingPathComponent("LyriaFlow", isDirectory: true)
        self.logDirectory = logsDir
        self.logFileURL = logsDir.appendingPathComponent("lyriaflow.log")

        self.dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        try? fileManager.createDirectory(at: logsDir, withIntermediateDirectories: true)
        log("LyriaFlow Logger initialized. Log path: \(logFileURL.path)", category: "SYSTEM")
    }

    public func log(_ message: String, category: String = "APP", level: String = "INFO") {
        let timestamp = dateFormatter.string(from: Date())
        let formattedLine = "[\(timestamp)] [\(level)] [\(category)] \(message)\n"

        // Print to console
        print(formattedLine, terminator: "")

        // Write to log file
        lock.lock()
        defer { lock.unlock() }

        if let data = formattedLine.data(using: .utf8) {
            if fileManager.fileExists(atPath: logFileURL.path) {
                if let fileHandle = try? FileHandle(forWritingTo: logFileURL) {
                    defer { try? fileHandle.close() }
                    _ = try? fileHandle.seekToEnd()
                    try? fileHandle.write(contentsOf: data)
                }
            } else {
                try? data.write(to: logFileURL, options: .atomic)
            }
        }
    }

    public func error(_ message: String, category: String = "APP") {
        log(message, category: category, level: "ERROR")
    }

    public func warning(_ message: String, category: String = "APP") {
        log(message, category: category, level: "WARN")
    }

    public func mcp(_ message: String) {
        log(message, category: "MCP")
    }

    public func revealLogInFinder() {
        if fileManager.fileExists(atPath: logFileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([logFileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: logDirectory.path)
        }
    }

    public func getRecentLogs(maxLines: Int = 100) -> String {
        lock.lock()
        defer { lock.unlock() }

        guard let content = try? String(contentsOf: logFileURL, encoding: .utf8) else {
            return "No logs available."
        }
        let lines = content.components(separatedBy: .newlines)
        let slice = lines.suffix(maxLines)
        return slice.joined(separator: "\n")
    }
}
