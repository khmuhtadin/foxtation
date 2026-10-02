import Foundation
import AVFoundation

enum RecorderError: LocalizedError {
    case noInputDevice
    case engineFailed(String)
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .noInputDevice: return "No microphone input available."
        case .engineFailed(let m): return "Audio engine failed: \(m)"
        case .emptyRecording: return "Nothing was recorded."
        }
    }
}

/// Captures the default input device, converts to 16 kHz mono Float32 in the
/// audio thread, and hands back a temporary WAV file for whisper.cpp.
final class Recorder {

    private var engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: 16_000,
                                             channels: 1,
                                             interleaved: false)!
    // `converter` and `samples` are touched by the audio thread; guard with `lock`.
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var samples: [Float] = []
    private var tapInstalled = false
    private var autoStopTimer: Timer?
    private var configObserver: NSObjectProtocol?

    private(set) var isRecording = false

    /// Called on the main thread with a 0…1 loudness value.
    var onLevel: ((Float) -> Void)?
    /// Called on the main thread when the max duration is reached or the
    /// input device goes away mid-recording.
    var onAutoStop: (() -> Void)?

    var maxSeconds: Double = 120

    // MARK: - Control

    func start() throws {
        guard !isRecording else { return }

        // A fresh engine picks up the current default input device and format.
        engine = AVAudioEngine()
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else {
            throw RecorderError.noInputDevice
        }
        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw RecorderError.engineFailed("cannot convert \(inputFormat.sampleRate) Hz to 16 kHz")
        }
        lock.lock()
        self.converter = converter
        samples.removeAll(keepingCapacity: true)
        samples.reserveCapacity(16_000 * 16)
        lock.unlock()

        input.installTap(onBus: 0, bufferSize: 2048, format: inputFormat) { [weak self] buffer, _ in
            self?.consume(buffer)
        }
        tapInstalled = true

        engine.prepare()
        do {
            try engine.start()
        } catch {
            teardown()
            throw RecorderError.engineFailed(error.localizedDescription)
        }

        isRecording = true

        autoStopTimer = Timer.scheduledTimer(withTimeInterval: maxSeconds, repeats: false) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onAutoStop?()
        }
        // Device unplugged / switched: the engine stops and no more buffers
        // arrive, so finish with what we have instead of listening forever.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            guard let self, self.isRecording else { return }
            self.onAutoStop?()
        }
    }

    /// Stops capture and writes the audio to a WAV file inside `directory`.
    @discardableResult
    func stop(writingTo directory: URL) throws -> (url: URL, duration: Double) {
        guard isRecording else { throw RecorderError.emptyRecording }
        teardown()

        lock.lock()
        let captured = samples
        samples.removeAll(keepingCapacity: true)
        lock.unlock()

        guard captured.count > 1_600 else { throw RecorderError.emptyRecording }  // < 0.1 s

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("capture-\(UUID().uuidString).wav")
        try WavWriter.write(samples: captured, sampleRate: targetFormat.sampleRate, to: url)
        return (url, Double(captured.count) / targetFormat.sampleRate)
    }

    func cancel() {
        guard isRecording else { return }
        teardown()
    }

    private func teardown() {
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        if let configObserver { NotificationCenter.default.removeObserver(configObserver) }
        configObserver = nil
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        engine.stop()
        lock.lock()
        converter = nil
        lock.unlock()
        isRecording = false
    }

    // MARK: - Audio thread

    private func consume(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        lock.lock()
        defer { lock.unlock() }
        guard let converter else { return }

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }

        var delivered = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, outStatus in
            if delivered {
                outStatus.pointee = .noDataNow
                return nil
            }
            delivered = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let channel = output.floatChannelData, output.frameLength > 0 else { return }

        let count = Int(output.frameLength)
        let pointer = channel[0]
        samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))

        var sum: Float = 0
        for i in 0..<count { sum += pointer[i] * pointer[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        let level = Float(max(0.0, min(1.0, (db + 60) / 60)))

        DispatchQueue.main.async { [weak self] in
            guard let self, self.isRecording else { return }
            self.onLevel?(level)
        }
    }
}
