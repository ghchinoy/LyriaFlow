import SwiftUI

public struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var coordinator: PlaybackCoordinator
    @Environment(\.dismiss) private var dismiss

    @State private var testingServer: Bool = false
    @State private var serverTestResult: String? = nil
    @State private var serverTestSuccess: Bool = false
    @State private var showingLogsCopied: Bool = false

    public init(settings: AppSettings, coordinator: PlaybackCoordinator) {
        self.settings = settings
        self.coordinator = coordinator
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("LyriaFlow Settings")
                    .font(.headline.weight(.bold))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Done, close settings")
            }
            .padding(16)
            .background(.ultraThinMaterial)

            Divider()

            Form {
                // Section: Gemini AI Suggestions
                Section(header: Text("Gemini Next-Track Suggestions").font(.subheadline.weight(.bold))) {
                    VStack(alignment: .leading, spacing: 6) {
                        SecureField("Gemini API Key (Google AI Studio)", text: $settings.storedGeminiApiKey)
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Gemini API Key input")

                        if !settings.storedGeminiApiKey.isEmpty {
                            Text("Using custom key saved in Settings.")
                                .font(.caption)
                                .foregroundColor(.green)
                        } else if !settings.effectiveGeminiApiKey.isEmpty {
                            Text(settings.geminiKeySourceDescription)
                                .font(.caption)
                                .foregroundColor(.green)
                        } else {
                            Text("No API key configured. Fallback musical variation templates will be used.")
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
                Section(header: Text("Lyria MCP Server (mcp-genmedia)").font(.subheadline.weight(.bold))) {
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
                Section(header: Text("Audio Tracks Persistence").font(.subheadline.weight(.bold))) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(settings.tracksDirectory.path)
                                .font(.caption.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        Button("Open in Finder") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: settings.tracksDirectory.path)
                        }
                    }
                }

                Divider()
                    .padding(.vertical, 8)

                // Section: Diagnostics & Logs
                Section(header: Text("Diagnostics & Logs").font(.subheadline.weight(.bold))) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(AppLogger.shared.logFileURL.path)
                                .font(.caption2.monospaced())
                                .foregroundColor(.secondary)
                                .lineLimit(1)

                            Spacer()

                            Button("Reveal Log") {
                                AppLogger.shared.revealLogInFinder()
                            }
                            .controlSize(.small)

                            Button(showingLogsCopied ? "Copied!" : "Copy Recent Logs") {
                                let logs = AppLogger.shared.getRecentLogs()
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(logs, forType: .string)
                                showingLogsCopied = true
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                    showingLogsCopied = false
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
            .padding(20)
        }
        .background(.ultraThinMaterial)
        .frame(width: 540, height: 540)
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
