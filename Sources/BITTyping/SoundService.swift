import AVFoundation
import Foundation

// MARK: - Playing Key Feedback

/// Responsive click mixer: overlapping key/error sounds each play on their
/// own player so rapid strokes never cut each other off — the same role as
/// `ClickSoundMixer` in `main.py`. Also owns a soft metronome tick.
final class SoundService: NSObject, @unchecked Sendable {

    // MARK: - Internal

    private var keyData: Data = Data()
    private var errorData: Data = Data()
    private var tickData: Data = Data()
    private var players: [AVAudioPlayer] = []
    private let lock = NSLock()

    override init() {
        super.init()
        AppSupport.ensureSeeded()
        ensureSoundFiles()
        keyData = (try? Data(contentsOf: AppSupport.sounds.appendingPathComponent("key.wav"))) ?? Data()
        errorData = (try? Data(contentsOf: AppSupport.sounds.appendingPathComponent("error.wav"))) ?? Data()
        tickData = Self.sineWav(frequency: 880, duration: 0.03, volume: 0.08)
    }

    /// Play key (`correct`) or error feedback. Safe to call from any thread.
    func play(correct: Bool) {
        let data = correct ? keyData : errorData
        guard !data.isEmpty else { return }
        play(data: data, volume: 1.0)
    }

    /// Soft metronome tick used while a timed lesson is running.
    func tick() {
        play(data: tickData, volume: 0.6)
    }

    // MARK: - Private

    private func play(data: Data, volume: Float) {
        guard !data.isEmpty else { return }
        do {
            let player = try AVAudioPlayer(data: data)
            player.volume = volume
            player.delegate = self
            lock.lock()
            players.append(player)
            // Cap polyphony; drop the oldest voice first.
            if players.count > 32 { players.removeFirst() }
            lock.unlock()
            player.play()
        } catch {
            // Stay silent rather than interrupting typing.
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

// MARK: - AVAudioPlayerDelegate

extension SoundService: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Player retention is best-effort; the 32-voice cap bounds growth.
    }
}
