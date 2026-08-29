import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var testingServer: Bool = false
    @State private var serverTestResult: String? = nil
    @State private var serverTestSuccess: Bool = false

    public init(settings: AppSettings, coordinator: PlaybackCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("LyriaFlow Settings")
                    .font(.headline)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
            .background(Color(nsColor: .windowBackgroundColor))

            Divider()

            Form {
                // Section: Gemini AI Suggestions
                Section(header: Text("Gemini Next-Track Suggestions").font(.subheadline).bold()) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("Gemini API Key (Google AI Studio)", text: $settings.storedGeminiApiKey)
                            .textFieldStyle(.roundedBorder)

                        if !settings.storedGeminiApiKey.isEmpty {
                            Text("Using custom user-configured API key.")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if let envKey = ProcessInfo.processInfo.environment["GEMINI_API_KEY"], !envKey.isEmpty {
                            Text("Using system environment key: \(envKey.prefix(8))...")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("No API key set. Fallback templates will be used for suggestions.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    }

                    Picker("Gemini Model", selection: $settings.geminiModel) {
                        ForEach(AppSettings.availableGeminiModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Section: Lyria MCP Server
                Section(header: Text("Lyria MCP Server (mcp-genmedia)").font(.subheadline).bold()) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Binary Path", text: $settings.customMcpBinaryPath, prompt: Text(settings.effectiveMcpBinaryPath))
                                .textFieldStyle(.roundedBorder)

                            Button("Test / Ping") {
                                testMcpServer()
                            }
                            .disabled(testingServer)
                        }

                        if let res = serverTestResult {
                            HStack(spacing: 4) {
                                Image(systemName: serverTestSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                                    .foregroundColor(serverTestSuccess ? .green : .red)
                                Text(res)
                                    .font(.caption)
                                    .foregroundColor(serverTestSuccess ? .green : .red)
                            }
                        }

                        Text("Origin: Google Cloud Vertex AI Creative Studio (mcp-genmedia)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    Picker("Default Music Model", selection: $settings.defaultModelId) {
                        ForEach(AppSettings.availableLyriaModels, id: \.self) { model in
                            Text(model).tag(model)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Section: Local Audio Storage
                Section(header: Text("Audio Tracks Persistence").font(.subheadline).bold()) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.tracksDirectory.path)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Open in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.tracksDirectory.path)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 480)
    }

    private func testMcpServer() {
        testingServer = true
        serverTestResult = nil
        Task {
            let client = MCPClient()
            let path = settings.effectiveMcpBinaryPath
            do {
                let (info, tools) = try await client.initializeAndVerify(binaryPath: path)
                await client.stop()
                serverTestSuccess = true
                serverTestResult = "Connected to \(info.name) \(info.version ?? ""). Found \(tools.count) tools."
                await coordinator.connectAndVerifyServer()
            } catch {
                serverTestSuccess = false
                serverTestResult = "Ping failed: \(error.localizedDescription)"
            }
            testingServer = false
        }
    }
}
