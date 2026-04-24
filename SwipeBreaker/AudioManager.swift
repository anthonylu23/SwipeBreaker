import AVFoundation
import Foundation

@MainActor
final class AudioManager {
    static let shared = AudioManager()

    enum Sound {
        case launch
        case bounce
        case brickHit
        case brickBreak
        case pickup
        case gameOver
    }

    var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: enabledKey)
            mixer.outputVolume = newValue ? volume : 0
        }
    }

    var volume: Float {
        get {
            guard UserDefaults.standard.object(forKey: volumeKey) != nil else { return 0.8 }
            return max(0, min(1, UserDefaults.standard.float(forKey: volumeKey)))
        }
        set {
            let clamped = max(0, min(1, newValue))
            UserDefaults.standard.set(clamped, forKey: volumeKey)
            mixer.outputVolume = isEnabled ? clamped : 0
        }
    }

    private let enabledKey = "swipebreaker.audio.enabled"
    private let volumeKey = "swipebreaker.audio.volume"
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var players: [Sound: AVAudioPlayerNode] = [:]
    private var buffers: [Sound: AVAudioPCMBuffer] = [:]
    private var lastPlayedAt: [Sound: TimeInterval] = [:]
    private var didStart = false

    private init() {
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        mixer.outputVolume = isEnabled ? volume : 0
        let format = engine.mainMixerNode.outputFormat(forBus: 0)

        let recipes: [(Sound, Double, Double, Double, Float)] = [
            (.launch,     220, 80,  0.16, 0.35),
            (.bounce,     720, 720, 0.04, 0.18),
            (.brickHit,   540, 380, 0.06, 0.22),
            (.brickBreak, 360, 120, 0.18, 0.32),
            (.pickup,     880, 1320, 0.18, 0.28),
            (.gameOver,   180, 60,  0.55, 0.40)
        ]
        for (sound, startHz, endHz, dur, amp) in recipes {
            let buffer = Self.makeTone(format: format, startHz: startHz, endHz: endHz, duration: dur, amplitude: amp)
            buffers[sound] = buffer
            let player = AVAudioPlayerNode()
            engine.attach(player)
            engine.connect(player, to: mixer, format: format)
            players[sound] = player
        }
    }

    func play(_ sound: Sound) {
        guard isEnabled else { return }
        startIfNeeded()
        let now = CACurrentMediaTime()
        if let last = lastPlayedAt[sound], now - last < minInterval(for: sound) { return }
        lastPlayedAt[sound] = now

        guard let player = players[sound], let buffer = buffers[sound] else { return }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
        if !player.isPlaying { player.play() }
    }

    func preview() {
        play(.pickup)
    }

    private func startIfNeeded() {
        guard !didStart else { return }
        do {
#if os(iOS) || os(tvOS) || os(watchOS)
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
            try session.setActive(true, options: [])
#endif
            try engine.start()
            didStart = true
        } catch {
            didStart = false
        }
    }

    private func minInterval(for sound: Sound) -> TimeInterval {
        switch sound {
        case .bounce: return 0.04
        case .brickHit: return 0.025
        default: return 0
        }
    }

    private static func makeTone(
        format: AVAudioFormat,
        startHz: Double,
        endHz: Double,
        duration: Double,
        amplitude: Float
    ) -> AVAudioPCMBuffer {
        let sampleRate = format.sampleRate
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channels = Int(format.channelCount)

        var phase: Double = 0
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / Double(frameCount)
            let freq = startHz + (endHz - startHz) * t
            let increment = 2.0 * .pi * freq / sampleRate
            phase += increment
            // attack-decay envelope: quick ramp up then exponential decay
            let attackEnd = 0.05
            let envelope: Double = t < attackEnd
                ? t / attackEnd
                : pow(1.0 - (t - attackEnd) / (1.0 - attackEnd), 1.6)
            let sample = Float(sin(phase) * envelope) * amplitude
            for channel in 0..<channels {
                buffer.floatChannelData?[channel][frame] = sample
            }
        }
        return buffer
    }
}
