import Foundation
import AppKit

public final class PersistenceStore: @unchecked Sendable {
    public static let shared = PersistenceStore()

    private let appSupportURL: URL
    private let databaseURL: URL
    public let tracksDirectory: URL
    private let fileManager = FileManager.default
    private let lock = NSLock()

    public init() {
        // App Support for JSON metadata database
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LyriaFlow", isDirectory: true)
        self.appSupportURL = appSupport
        self.databaseURL = appSupport.appendingPathComponent("tracks.json")

        // ~/Music/LyriaFlow/Tracks for audio files
        let musicDir = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Music")
            .appendingPathComponent("LyriaFlow")
            .appendingPathComponent("Tracks")
        self.tracksDirectory = musicDir

        try? fileManager.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: tracksDirectory, withIntermediateDirectories: true)
    }

    public func loadTracks() -> [Track] {
        lock.lock()
        defer { lock.unlock() }

        guard fileManager.fileExists(atPath: databaseURL.path) else {
            // Check if there are existing WAV files in the directory we can scan
            return scanExistingFiles()
        }

        do {
            let data = try Data(contentsOf: databaseURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let tracks = try decoder.decode([Track].self, from: data)
            return tracks.sorted(by: { $0.createdAt > $1.createdAt })
        } catch {
            print("⚠️ Failed to decode tracks database: \(error)")
            return []
        }
    }

    public func saveTracks(_ tracks: [Track]) {
        lock.lock()
        defer { lock.unlock() }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(tracks)
            try data.write(to: databaseURL, options: [.atomic])
        } catch {
            print("⚠️ Failed to save tracks: \(error)")
        }
    }

    public func audioFileURL(for track: Track) -> URL {
        return tracksDirectory.appendingPathComponent(track.audioFileName)
    }

    public func deleteTrack(_ track: Track, tracks: inout [Track]) {
        let fileURL = audioFileURL(for: track)
        try? fileManager.removeItem(at: fileURL)
        tracks.removeAll(where: { $0.id == track.id })
        saveTracks(tracks)
    }

    public func revealInFinder(for track: Track) {
        let fileURL = audioFileURL(for: track)
        if fileManager.fileExists(atPath: fileURL.path) {
            NSWorkspace.shared.activateFileViewerSelecting([fileURL])
        } else {
            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: tracksDirectory.path)
        }
    }

    private func scanExistingFiles() -> [Track] {
        guard let files = try? fileManager.contentsOfDirectory(atPath: tracksDirectory.path) else {
            return []
        }
        var found: [Track] = []
        for file in files where file.hasSuffix(".wav") {
            let filePath = tracksDirectory.appendingPathComponent(file)
            let attrs = try? fileManager.attributesOfItem(atPath: filePath.path)
            let modDate = attrs?[.modificationDate] as? Date ?? Date()

            let cleanPrompt = file
                .replacingOccurrences(of: ".wav", with: "")
                .replacingOccurrences(of: "spike_test_", with: "Spike Test: ")
                .replacingOccurrences(of: "_", with: " ")

            let track = Track(
                prompt: cleanPrompt,
                modelId: "lyria-3-clip-preview",
                createdAt: modDate,
                audioFileName: file
            )
            found.append(track)
        }
        found.sort(by: { $0.createdAt > $1.createdAt })
        saveTracks(found)
        return found
    }
}
