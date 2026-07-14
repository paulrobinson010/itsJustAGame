import AVFoundation
import Foundation

/// Microphone metering for the audio games (Loudest, Blow It Out, Hum It).
/// Everything is processed on the render thread and reduced to two numbers
/// — a 0–1 loudness and an estimated hum pitch — that the views read
/// synchronously. Raw audio is never recorded, stored, or transmitted.
final class MicService: @unchecked Sendable {
    static let shared = MicService()

    private let engine = AVAudioEngine()
    private let lock = NSLock()
    private var _level = 0.0
    private var _peak = 0.0
    private var _pitch = 0.0
    private(set) var isRunning = false

    /// Instantaneous loudness, 0 (silence) to 1 (very loud).
    var level: Double { lock.lock(); defer { lock.unlock() }; return _level }
    /// Loudest level seen since the last resetPeak().
    var peak: Double { lock.lock(); defer { lock.unlock() }; return _peak }
    /// Estimated fundamental of a hum, in Hz (0 if none detected).
    var pitchHz: Double { lock.lock(); defer { lock.unlock() }; return _pitch }

    func resetPeak() {
        lock.lock(); _peak = 0; lock.unlock()
    }

    /// Requests permission (once) and starts metering. Returns false if the
    /// mic is unavailable or the user declined.
    ///
    /// `measurement` mode strips output processing so a shout isn't
    /// auto-attenuated (right for Loudest/Blow It Out) — but it also
    /// silences playback, so Hum It, which plays a reference tone, passes
    /// `measurement: false` to keep the note audible.
    func start(measurement: Bool = true) async -> Bool {
        guard !isRunning else { return true }
        guard await requestPermission() else { return false }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord,
                                    mode: measurement ? .measurement : .default,
                                    options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                self?.process(buffer)
            }
            engine.prepare()
            try engine.start()
            isRunning = true
            return true
        } catch {
            return false
        }
    }

    func stop() {
        guard isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        lock.lock(); _level = 0; _pitch = 0; lock.unlock()
        try? AVAudioSession.sharedInstance().setActive(false, options: [.notifyOthersOnDeactivation])
    }

    private func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func process(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let n = Int(buffer.frameLength)
        guard n > 0 else { return }

        var sumSquares = 0.0
        for i in 0..<n {
            let s = Double(channel[i])
            sumSquares += s * s
        }
        let rms = (sumSquares / Double(n)).squareRoot()
        // Map roughly -50 dBFS…0 dBFS onto 0…1.
        let db = 20 * log10(max(rms, 1e-7))
        let level = min(1.0, max(0.0, (db + 50) / 50))

        let pitch = estimatePitch(channel, count: n, sampleRate: buffer.format.sampleRate, energy: sumSquares)

        lock.lock()
        _level = level
        _peak = max(_peak, level)
        if let pitch { _pitch = pitch }
        lock.unlock()
    }

    /// Autocorrelation pitch estimate over the hum range (80–500 Hz).
    private func estimatePitch(_ data: UnsafeMutablePointer<Float>, count n: Int, sampleRate: Double, energy: Double) -> Double? {
        guard energy > 0.02 else { return nil }  // too quiet to be a hum
        let minLag = max(1, Int(sampleRate / 500))
        let maxLag = min(n - 1, Int(sampleRate / 80))
        guard maxLag > minLag else { return nil }
        var bestLag = -1
        var bestCorr = 0.0
        var lag = minLag
        while lag <= maxLag {
            var corr = 0.0
            var i = 0
            let limit = n - lag
            while i < limit {
                corr += Double(data[i]) * Double(data[i + lag])
                i += 1
            }
            if corr > bestCorr {
                bestCorr = corr
                bestLag = lag
            }
            lag += 1
        }
        guard bestLag > 0 else { return nil }
        return sampleRate / Double(bestLag)
    }
}

/// Builds a short sine-tone WAV in memory for Hum It's reference note —
/// played through AVAudioPlayer alongside the mic (playAndRecord session).
enum ToneWAV {
    static func data(frequency: Double, seconds: Double, sampleRate: Double = 44_100) -> Data {
        let frameCount = Int(seconds * sampleRate)
        var samples = [Int16]()
        samples.reserveCapacity(frameCount)
        let twoPiF = 2.0 * Double.pi * frequency
        for i in 0..<frameCount {
            let t = Double(i) / sampleRate
            // Gentle fade in/out to avoid clicks.
            let env = min(1.0, min(Double(i), Double(frameCount - i)) / (sampleRate * 0.02))
            let value = sin(twoPiF * t) * env * 0.6
            samples.append(Int16(max(-1, min(1, value)) * 32_767))
        }

        var data = Data()
        let byteRate = Int(sampleRate) * 2
        let dataSize = samples.count * 2
        func append(_ string: String) { data.append(string.data(using: .ascii)!) }
        func append32(_ value: Int) { var v = UInt32(value).littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }
        func append16(_ value: Int) { var v = UInt16(value).littleEndian; withUnsafeBytes(of: &v) { data.append(contentsOf: $0) } }

        append("RIFF"); append32(36 + dataSize); append("WAVE")
        append("fmt "); append32(16); append16(1); append16(1)
        append32(Int(sampleRate)); append32(byteRate); append16(2); append16(16)
        append("data"); append32(dataSize)
        samples.withUnsafeBytes { data.append(contentsOf: $0) }
        return data
    }
}
