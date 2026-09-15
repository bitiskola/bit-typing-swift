import AVFoundation
import Foundation

// MARK: - Playing Key Feedback

/// Responsive click mixer: overlapping key/error sounds each play on their
/// own player so rapid strokes never cut each other off — the same role as
/// `ClickSoundMixer` in `main.py`. Also owns a soft metronome tick.
final class SoundService: @unchecked Sendable {

    // MARK: - Internal

    // Fixed pools of pre-buffered players, round-robined per hit. The old
    // code built a fresh `AVAudioPlayer(data:)` on the main thread for every
    // keystroke (parse + AudioQueue setup per press), which lagged typing
    // feedback on slower Macs. Prepared players make `play()` near-instant.
    private var keyPlayers: [AVAudioPlayer] = []
    private var errorPlayers: [AVAudioPlayer] = []
    private var tickPlayer: AVAudioPlayer? = nil
    private var keyCursor = 0
    private var errorCursor = 0
    private let lock = NSLock()
    private static let poolSize = 8

    init() {
        AppSupport.ensureSeeded()
        ensureSoundFiles()
        keyPlayers = Self.preparedPlayers(
            url: AppSupport.sounds.appendingPathComponent("key.wav"), count: Self.poolSize)
        errorPlayers = Self.preparedPlayers(
            url: AppSupport.sounds.appendingPathComponent("error.wav"), count: Self.poolSize)
        tickPlayer = try? AVAudioPlayer(data: Self.sineWav(frequency: 880, duration: 0.03, volume: 0.08))
        tickPlayer?.prepareToPlay()
    }

    /// Play key (`correct`) or error feedback. Safe to call from any thread.
    func play(correct: Bool) {
        lock.lock()
        defer { lock.unlock() }
        if correct {
            guard !keyPlayers.isEmpty else { return }
            let player = keyPlayers[keyCursor]
            keyCursor = (keyCursor + 1) % keyPlayers.count
            player.volume = 1.0
            player.currentTime = 0
            player.play()
        } else {
            guard !errorPlayers.isEmpty else { return }
            let player = errorPlayers[errorCursor]
            errorCursor = (errorCursor + 1) % errorPlayers.count
            player.volume = 1.0
            player.currentTime = 0
            player.play()
        }
    }

    /// Soft metronome tick used while a timed lesson is running.
    func tick() {
        lock.lock()
        defer { lock.unlock() }
        guard let player = tickPlayer else { return }
        player.volume = 0.6
        player.currentTime = 0
        player.play()
    }

    // MARK: - Private

    /// Up to `count` players pre-buffered via `prepareToPlay`, so first and
    /// later hits cost the same. Empty when the file is missing — the app
    /// stays silent instead of interrupting typing.
    private static func preparedPlayers(url: URL, count: Int) -> [AVAudioPlayer] {
        guard let data = try? Data(contentsOf: url), !data.isEmpty else { return [] }
        return (0..<count).compactMap { _ in
            guard let player = try? AVAudioPlayer(data: data) else { return nil }
            player.prepareToPlay()
            return player
        }
    }

    /// Synthesize the two bundled click files when they are missing,
    /// using the exact recipe from `_ensure_sound_files()` in `main.py`.
    private func ensureSoundFiles() {
        let specs: [(name: String, frequency: Double, duration: Double, volume: Double)] = [
            ("key.wav", 1350, 0.022, 0.16),
            ("error.wav", 260, 0.075, 0.24),
        ]
        for spec in specs {
            let url = AppSupport.sounds.appendingPathComponent(spec.name)
            if FileManager.default.fileExists(atPath: url.path) { continue }
            let wav = Self.sineWav(frequency: spec.frequency, duration: spec.duration, volume: spec.volume)
            try? wav.write(to: url)
        }
    }

    private static func sineWav(frequency: Double, duration: Double, volume: Double, rate: Int = 22050) -> Data {
        let frames = Int(Double(rate) * duration)
        var data = Data()
        data.reserveCapacity(44 + frames * 2)
        func append16(_ value: Int) {
            var v = Int16(clamping: value).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        func append32(_ value: Int) {
            var v = Int32(value).littleEndian
            withUnsafeBytes(of: &v) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: [UInt8]("RIFF".utf8)); append32(36 + frames * 2)
        data.append(contentsOf: [UInt8]("WAVE".utf8)); data.append(contentsOf: [UInt8]("fmt ".utf8))
        append32(16); append16(1); append16(1); append32(rate); append32(rate * 2); append16(2); append16(16)
        data.append(contentsOf: [UInt8]("data".utf8)); append32(frames * 2)
        for sample in 0..<frames {
            let position = Double(sample) / Double(rate)
            let envelope = max(0.0, 1.0 - position / duration)
            let value = Int(32767 * volume * envelope * envelope * sin(2 * .pi * frequency * position))
            append16(value)
        }
        return data
    }
}

