import Foundation

/// Discovers, loads, and merges environment variables for LyriaFlow across macOS GUI launchd sessions,
/// user shell configurations (~/.zshrc, ~/.zshenv), gcloud Application Default Credentials, and .env files.
public final class EnvironmentLoader: @unchecked Sendable {
    public static let shared = EnvironmentLoader()

    private var envMap: [String: String] = [:]
    private var hasLoadedFileConfigs = false
    private let lock = NSLock()
    private let homeDir: URL

    private init() {
        self.homeDir = FileManager.default.homeDirectoryForCurrentUser
        loadBasicEnvironment()
    }

    /// Initializes basic system paths and environment variables in memory without performing disk I/O.
    private func loadBasicEnvironment() {
        lock.lock()
        defer { lock.unlock() }

        var merged = ProcessInfo.processInfo.environment
        let homePath = homeDir.path
        let user = ProcessInfo.processInfo.userName
        if merged["HOME"] == nil || merged["HOME"]?.isEmpty == true {
            merged["HOME"] = homePath
        }
        if merged["USER"] == nil || merged["USER"]?.isEmpty == true {
            merged["USER"] = user
        }

        let defaultPaths = [
            "\(homePath)/go/bin",
            "\(homePath)/.local/bin",
            "/opt/homebrew/bin",
            "/opt/homebrew/sbin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        let currentPath = merged["PATH"] ?? ""
        var pathComponents = currentPath.split(separator: ":").map(String.init)
        for p in defaultPaths where !pathComponents.contains(p) {
            pathComponents.append(p)
        }
        merged["PATH"] = pathComponents.joined(separator: ":")

        self.envMap = merged
    }

    /// Asynchronously discovers and loads environment files in the background.
    public func loadEnvironmentAsync() async {
        await Task.detached(priority: .utility) { [self] in
            self.loadEnvironment()
        }.value
    }

    public func loadEnvironment() {
        lock.lock()
        defer { lock.unlock() }
        loadEnvironmentLocked()
    }

    private func loadEnvironmentLocked() {
        var merged = envMap

        // 1. Auto-discover Google Application Default Credentials (ADC) if unset
        if merged["GOOGLE_APPLICATION_CREDENTIALS"] == nil || merged["GOOGLE_APPLICATION_CREDENTIALS"]?.isEmpty == true {
            let adcURL = homeDir.appendingPathComponent(".config/gcloud/application_default_credentials.json")
            if FileManager.default.fileExists(atPath: adcURL.path) {
                merged["GOOGLE_APPLICATION_CREDENTIALS"] = adcURL.path
                AppLogger.shared.log("Auto-discovered Google Cloud ADC at: \(adcURL.path)", category: "ENV")
            }
        }

        // 2. Scan .env files
        let envFileCandidates = [
            homeDir.appendingPathComponent("Music/LyriaFlow/.env"),
            homeDir.appendingPathComponent(".config/lyriaflow/.env"),
            homeDir.appendingPathComponent(".config/lyriaflow/env"),
            homeDir.appendingPathComponent(".env"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env")
        ]

        for envURL in envFileCandidates where FileManager.default.fileExists(atPath: envURL.path) {
            parseEnvFile(at: envURL, into: &merged)
        }

        // 3. Scan ~/.zshenv and ~/.zshrc for exported variables (critical for GUI launchd apps)
        let shellConfigs = [
            homeDir.appendingPathComponent(".zshenv"),
            homeDir.appendingPathComponent(".zshrc"),
            homeDir.appendingPathComponent(".bash_profile"),
            homeDir.appendingPathComponent(".bashrc")
        ]

        for shellURL in shellConfigs where FileManager.default.fileExists(atPath: shellURL.path) {
            parseShellExports(at: shellURL, into: &merged)
        }

        self.envMap = merged
        self.hasLoadedFileConfigs = true
    }

    private func parseEnvFile(at url: URL, into dict: inout [String: String]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                var val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                    val = String(val.dropFirst().dropLast())
                }
                if dict[key] == nil || dict[key]?.isEmpty == true {
                    dict[key] = val
                    AppLogger.shared.log("Loaded \(key) from .env at \(url.lastPathComponent)", category: "ENV")
                }
            }
        }
    }

    private func parseShellExports(at url: URL, into dict: inout [String: String]) {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return }
        let targetKeys = [
            "GEMINI_API_KEY",
            "GOOGLE_APPLICATION_CREDENTIALS",
            "GOOGLE_CLOUD_PROJECT",
            "VERTEX_AI_PROJECT",
            "MCP_LYRIA_BINARY"
        ]

        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.hasPrefix("export ") else { continue }
            let exportBody = String(trimmed.dropFirst(7)).trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = exportBody.split(separator: "=", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
                if targetKeys.contains(key) {
                    var val = parts[1].trimmingCharacters(in: .whitespacesAndNewlines)
                    if (val.hasPrefix("\"") && val.hasSuffix("\"")) || (val.hasPrefix("'") && val.hasSuffix("'")) {
                        val = String(val.dropFirst().dropLast())
                    }
                    if dict[key] == nil || dict[key]?.isEmpty == true {
                        dict[key] = val
                        AppLogger.shared.log("Loaded \(key) from shell config: \(url.lastPathComponent)", category: "ENV")
                    }
                }
            }
        }
    }

    public func value(for key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if !hasLoadedFileConfigs {
            loadEnvironmentLocked()
        }
        if let v = envMap[key], !v.isEmpty {
            return v
        }
        return nil
    }

    public func resolvedEnvironment() -> [String: String] {
        lock.lock()
        defer { lock.unlock() }
        if !hasLoadedFileConfigs {
            loadEnvironmentLocked()
        }
        return envMap
    }
}
