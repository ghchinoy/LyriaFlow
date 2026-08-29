import Foundation
import AVFoundation
import Combine

@MainActor
public final class AudioEngine: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public var isPlaying: Bool = false
    @Published public var currentTime: TimeInterval = 0
    @Published public var duration: TimeInterval = 0
    @Published public var powerLevels: [Float] = Array(repeating: 0.04, count: 32)
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
    public static let barCount: Int = 32
    private var barCount: Int { Self.barCount }

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
        if p.duration > 0 && p.currentTime >= p.duration - 0.05 {
            p.currentTime = 0
            self.currentTime = 0
        }
        p.play()
        isPlaying = true
        startMetering()
    }

    public func pause() {
        guard let p = player else { return }
        p.pause()
        isPlaying = false
        stopMetering()
        powerLevels = Array(repeating: 0.04, count: barCount)
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
        powerLevels = Array(repeating: 0.04, count: barCount)
    }

    public func seek(to time: TimeInterval) {
        guard let p = player, p.duration > 0, !time.isNaN else { return }
        p.currentTime = max(0, min(time, p.duration))
        self.currentTime = p.currentTime
    }

    private func startMetering() {
        stopMetering()
        let timer = Timer(timeInterval: 0.04, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.updateAudioMetrics()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.meterTimer = timer
    }

    private func stopMetering() {
        meterTimer?.invalidate()
        meterTimer = nil
    }

    private func updateAudioMetrics() {
        guard let p = player, p.isPlaying else {
            powerLevels = Array(repeating: 0.04, count: barCount)
            return
        }
        p.updateMeters()
        self.currentTime = p.currentTime

        // Read power from available channels
        let avgPower0 = p.averagePower(forChannel: 0) // dB (-160 to 0)
        let peakPower0 = p.peakPower(forChannel: 0)

        let avgPower1 = p.numberOfChannels > 1 ? p.averagePower(forChannel: 1) : avgPower0
        let peakPower1 = p.numberOfChannels > 1 ? p.peakPower(forChannel: 1) : peakPower0

        // Convert dB to linear dynamic normalized power (0.0 to 1.0) with -60dB noise floor
        let normAvg0 = max(0.0, min(1.0, (avgPower0 + 60.0) / 60.0))
        let normPeak0 = max(0.0, min(1.0, (peakPower0 + 60.0) / 60.0))
        let normAvg1 = max(0.0, min(1.0, (avgPower1 + 60.0) / 60.0))
        let normPeak1 = max(0.0, min(1.0, (peakPower1 + 60.0) / 60.0))

        // Multi-band spectrum calculation across 32 bars
        var newLevels: [Float] = []
        newLevels.reserveCapacity(barCount)

        for i in 0..<barCount {
            // Spatial balance: left channel weights lower indices, right channel weights higher indices
            let channelFraction = Float(i) / Float(barCount - 1)
            let avgPower = normAvg0 * (1.0 - channelFraction) + normAvg1 * channelFraction
            let peakPower = normPeak0 * (1.0 - channelFraction) + normPeak1 * channelFraction

            // Frequency envelope curve across 32 bands:
            // Bass (0-7): heavy low-end boost, punchy response to peak
            // Mids (8-19): harmonic curve centered on vocal/instrumental frequencies
            // Highs (20-31): crisp transient response to peak power
            let bandPosition = Float(i) / Float(barCount)
            let bassWeight: Float = (i < 8) ? (1.35 - Float(i) * 0.05) : 0.85
            let midWeight: Float = Float(sin(Double(bandPosition) * .pi)) * 1.15
            let trebleWeight: Float = (i >= 20) ? (0.8 + Float(i - 20) * 0.035) : 0.7

            // Dynamic flutter per frequency bin for organic visual texture
            let harmonicFlutter = Float.random(in: 0.90...1.10)
            let transientKick = peakPower * 0.32 * (i % 2 == 0 ? 1.08 : 0.92)

            let rawVal = (avgPower * 0.65 * bassWeight + avgPower * 0.35 * midWeight + transientKick * trebleWeight) * harmonicFlutter

            // Squeeze into 0.04 (resting baseline) to 1.0 (max peak)
            let clamped = max(0.04, min(1.0, rawVal))
            newLevels.append(clamped)
        }

        self.powerLevels = newLevels
    }

    // MARK: - AVAudioPlayerDelegate
    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.currentTime = self.duration
            self.stopMetering()
            self.powerLevels = Array(repeating: 0.04, count: Self.barCount)
            if flag && !self.isLooping {
                self.onTrackFinished?()
            }
        }
    }
}
