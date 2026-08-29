import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var powerLevels: [Float] = Array(repeating: 0.1, count: 24)
    @Published public var currentURL: URL? = nil
    @Published public var volume: Float = 0.85 {
        didSet {
            player?.volume = volume
        }
    }
    @Published public var isLooping: Bool = false {
        didSet {
            player?.numberOfLoops = isLooping ? -1 : 0
        }
    }

    public var onTrackFinished: (() -> Void)?

    private var player: AVAudioPlayer?
    private var meterTimer: Timer?
    private let barCount: Int = 24

    public override init() {
        super.init()
    }

    public func loadAndPlay(url: URL) throws {
        stop()

        guard FileManager.default.fileExists(atPath: url.path) else {
            throw NSError(domain: "AudioEngine", code: 404, userInfo: [NSLocalizedDescriptionKey: "Audio file not found at \(url.path)"])
        }

        let p = try AVAudioPlayer(contentsOf: url)
        p.delegate = self
        p.isMeteringEnabled = true
        p.volume = volume
        p.numberOfLoops = isLooping ? -1 : 0
        p.prepareToPlay()

        self.player = p
        self.currentURL = url
        self.duration = p.duration
        self.currentTime = 0

        p.play()
        self.isPlaying = true
        startMetering()
    }

    public func play() {
        guard let p = player else { return }
        p.play()
        isPlaying = true
        startMetering()
    }

    public func pause() {
        guard let p = player else { return }
        p.pause()
        isPlaying = false
        stopMetering()
    }

    public func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    public func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        currentURL = nil
        stopMetering()
        powerLevels = Array(repeating: 0.05, count: barCount)
    }

    public func seek(to time: TimeInterval) {
        guard let p = player else { return }
        p.currentTime = max(0, min(time, p.duration))
        self.currentTime = p.currentTime
    }

    private func startMetering() {
        stopMetering()
        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                self.updateAudioMetrics()
            }
        }
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateAudioMetrics() {
        guard let p = player, p.isPlaying else { return }
        p.updateMeters()
        self.currentTime = p.currentTime

        let avgPower = p.averagePower(forChannel: 0) // dB (-160 to 0)
        let peakPower = p.peakPower(forChannel: 0)

        // Convert dB to normalized linear 0.0 ... 1.0
        let normAvg = max(0.05, pow(10.0, avgPower / 20.0))
        let normPeak = max(0.08, pow(10.0, peakPower / 20.0))

        // Create animated bars with slight frequency-like variations
        var newLevels: [Float] = []
        for i in 0..<barCount {
            let frequencyWeight = sin(Double(i) / Double(barCount) * .pi)
            let randomFlutter = Float.random(in: 0.85...1.15)
            let val = Float(normAvg * Float(0.5 + 0.5 * frequencyWeight) * randomFlutter + normPeak * 0.3)
            newLevels.append(min(1.0, max(0.05, val)))
        }
        self.powerLevels = newLevels
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopMetering()
            if flag && !self.isLooping {
                self.onTrackFinished?()
            }
        }
    }
}
