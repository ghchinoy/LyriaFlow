import Foundation

/// Utility to detect audio container formats from raw binary headers (magic bytes)
/// ensuring correct file extensions and preserving cryptographic provenance (such as C2PA ID3 GEOB frames).
public struct AudioFormatDetector: Sendable {

    public enum AudioFormat: String, Sendable, CaseIterable {
        case mp3 = "mp3"
        case wav = "wav"
        case flac = "flac"
        case m4a = "m4a"
        case aac = "aac"
        case unknown = "unknown"

        public var fileExtension: String {
            switch self {
            case .mp3: return "mp3"
            case .wav: return "wav"
            case .flac: return "flac"
            case .m4a: return "m4a"
            case .aac: return "aac"
            case .unknown: return "mp3" // Default fallback for Lyria AI
            }
        }

        public var displayName: String {
            switch self {
            case .mp3: return "MP3 Audio (MPEG Layer 3)"
            case .wav: return "WAV Audio (RIFF PCM)"
            case .flac: return "FLAC Audio (Lossless)"
            case .m4a: return "M4A Audio (AAC/ALAC)"
            case .aac: return "AAC Audio Stream"
            case .unknown: return "Audio File"
            }
        }
    }

    /// Inspects the first 16 bytes of data to determine the audio container format.
    public static func detectFormat(from data: Data) -> AudioFormat {
        guard data.count >= 4 else { return .unknown }

        let bytes = [UInt8](data.prefix(16))

        // 1. ID3v2 container (Standard for MP3 with metadata / C2PA GEOB frames): "ID3"
        if bytes.count >= 3 && bytes[0] == 0x49 && bytes[1] == 0x44 && bytes[2] == 0x33 {
            return .mp3
        }

        // 2. Raw MPEG-1/2 Audio Layer 3 frame sync: 0xFF 0xFB, 0xFF 0xF3, 0xFF 0xF2, 0xFF 0xFA
        if bytes.count >= 2 && bytes[0] == 0xFF && (bytes[1] & 0xE0) == 0xE0 {
            // Further verify layer 3 bits (bits 1-2 of byte 1: 01 = Layer 3)
            let layer = (bytes[1] >> 1) & 0x03
            if layer == 0x01 {
                return .mp3
            }
        }

        // 3. RIFF WAVE: "RIFF" .... "WAVE"
        if bytes.count >= 12 &&
            bytes[0] == 0x52 && bytes[1] == 0x49 && bytes[2] == 0x46 && bytes[3] == 0x46 &&
            bytes[8] == 0x57 && bytes[9] == 0x41 && bytes[10] == 0x56 && bytes[11] == 0x45 {
            return .wav
        }

        // 4. FLAC: "fLaC"
        if bytes.count >= 4 && bytes[0] == 0x66 && bytes[1] == 0x4C && bytes[2] == 0x61 && bytes[3] == 0x43 {
            return .flac
        }

        // 5. ISO Base Media / MP4 / M4A: "....ftyp"
        if bytes.count >= 8 && bytes[4] == 0x66 && bytes[5] == 0x74 && bytes[6] == 0x79 && bytes[7] == 0x70 {
            return .m4a
        }

        return .unknown
    }

    /// Inspects a file on disk to determine its true container format from magic bytes.
    public static func detectFormat(for fileURL: URL) -> AudioFormat {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            // Fall back to filename extension
            return formatFromExtension(fileURL.pathExtension)
        }
        defer { try? fileHandle.close() }

        guard let headerData = try? fileHandle.read(upToCount: 32), !headerData.isEmpty else {
            return formatFromExtension(fileURL.pathExtension)
        }

        let detected = detectFormat(from: headerData)
        if detected != .unknown {
            return detected
        }
        return formatFromExtension(fileURL.pathExtension)
    }

    /// Determines the appropriate file extension given the payload data or filename.
    public static func preferredExtension(for data: Data, fallback: String = "mp3") -> String {
        let detected = detectFormat(from: data)
        return detected == .unknown ? fallback : detected.fileExtension
    }

    private static func formatFromExtension(_ ext: String) -> AudioFormat {
        switch ext.lowercased() {
        case "mp3": return .mp3
        case "wav": return .wav
        case "flac": return .flac
        case "m4a", "mp4": return .m4a
        case "aac": return .aac
        default: return .unknown
        }
    }
}
