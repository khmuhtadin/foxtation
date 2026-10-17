import AVFoundation
import Foundation
@preconcurrency import WhisperKit

/// On-device Whisper large-v3-turbo on the Neural Engine (Argmax WhisperKit).
/// The model stays loaded, and a `Session` transcribes finished stretches of
/// speech while the user is still talking, so after release only the tail is
/// left. Measured on an M4: about 0.5 s from release to text.
final class WhisperKitEngine {

    static let shared = WhisperKitEngine()
    static let modelName = "openai_whisper-large-v3-v20240930_turbo"

    enum State: Equatable {
        case notInstalled
        case downloading(Double)
        /// The first load compiles the model for the Neural Engine (about a minute, once).
        case loading
        case ready
        case failed(String)
    }

    /// Main thread. Drives the Engine settings row.
    private(set) var state: State = .notInstalled {
        didSet { DispatchQueue.main.async { self.onStateChange?() } }
    }
    var onStateChange: (() -> Void)?

    /// WhisperKit isn't Sendable. One instance is shared and used one call at a time.
    final class Model: @unchecked Sendable {
        let kit: WhisperKit
        init(_ kit: WhisperKit) { self.kit = kit }
    }

    private let lock = NSLock()
    private var loadTask: Task<Model, Error>?

    private init() {
        // Installed but not loaded yet: the app prewarms it at launch.
        if isInstalled { state = .loading }
    }

    static var downloadBase: URL { AppPaths.support.appendingPathComponent("whisperkit", isDirectory: true) }
    static var modelFolder: URL {
        downloadBase.appendingPathComponent("models/argmaxinc/whisperkit-coreml/\(modelName)", isDirectory: true)
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.modelFolder.appendingPathComponent("AudioEncoder.mlmodelc").path)
    }

    // MARK: - Setup

    /// Downloads the model (about 1.5 GB) if needed, then loads it.
    func install() {
        guard !isInstalled else { prewarm(); return }
        Task {
            do {
                state = .downloading(0)
                _ = try await WhisperKit.download(variant: Self.modelName, downloadBase: Self.downloadBase) { progress in
                    self.state = .downloading(progress.fractionCompleted)
                }
                _ = try await load()
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Loads the model in the background if it's installed and not loaded yet.
    func prewarm() {
        guard isInstalled else { return }
        Task { _ = try? await load() }
    }

    /// The loaded model. The first caller starts the load; everyone shares it.
    /// A failed load is forgotten so the next call tries again.
    func load() async throws -> Model {
        let task: Task<Model, Error> = lock.withLock {
            if let loadTask { return loadTask }
            let task = Task<Model, Error> {
                self.state = .loading
                let config = WhisperKitConfig(modelFolder: Self.modelFolder.path, tokenizerFolder: Self.downloadBase,
                                              verbose: false, logLevel: .error,
                                              prewarm: true, load: true, download: false)
                return Model(try await WhisperKit(config))
            }
            loadTask = task
            return task
        }
        do {
            let model = try await task.value
            if state != .ready { state = .ready }
            return model
        } catch {
            lock.withLock { loadTask = nil }
            state = .failed(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Transcription

    /// `language` nil detects it. Returns the text and the language used.
    func transcribe(_ samples: [Float], language: String?) async throws -> (text: String, language: String) {
        let kit = try await load().kit
        let options = DecodingOptions(task: .transcribe,
                                      language: language,
                                      temperature: 0,
                                      usePrefillPrompt: true,
                                      detectLanguage: language == nil,
                                      skipSpecialTokens: true,
                                      withoutTimestamps: true)
        let results = try await kit.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return (text, results.first?.language ?? language ?? "auto")
    }

    /// Reads a WAV (any rate) as 16 kHz mono floats, for the CLI.
    static func samples(of url: URL) throws -> [Float] {
        try AudioProcessor.loadAudioAsFloatArray(fromPath: url.path)
    }

    // MARK: - Transcribing while recording

    /// Gets the recorder's 16 kHz samples as they arrive. At each pause of at
    /// least 0.25 s after 3 s of audio it transcribes that stretch in the
    /// background (one at a time, in order); `finish()` transcribes the tail and
    /// joins everything.
    final class Session {
        static let sampleRate = 16_000
        private static let frame = 1_600                 // 100 ms
        private static let silenceDB: Float = -40
        private static let minChunk = 3.0                // seconds before a cut is allowed
        private static let pauseToCut = 0.25             // seconds of silence that end a chunk
        private static let maxChunk = 25.0               // Whisper sees 30 s at a time

        private let engine: WhisperKitEngine
        private let queue = DispatchQueue(label: "foxtation.whisperkit.session")
        private var incoming: [Float] = []               // not yet a whole frame
        private var pending: [Float] = []                // since the last cut
        private var silence = 0.0
        private var language: String?
        /// The chain of chunk transcriptions; each waits for the one before.
        private var last: Task<[String], Error>?

        init(engine: WhisperKitEngine = .shared, language: String) {
            self.engine = engine
            self.language = language == "auto" ? nil : language
        }

        /// Any thread (the recorder calls it from the audio thread).
        func append(_ samples: [Float]) {
            queue.async { self.consume(samples) }
        }

        /// Transcribes what's left and returns the whole transcript.
        func finish() async throws -> Transcript {
            let started = Date()
            let tail: [Float] = queue.sync {
                pending += incoming
                incoming = []
                return pending
            }
            if Self.hasSpeech(tail) { enqueue(tail) }
            let parts = try await last?.value ?? []
            let text = parts.filter { !$0.isEmpty }.joined(separator: " ")
            return Transcript(text: text, language: language ?? "auto", duration: Date().timeIntervalSince(started))
        }

        private func consume(_ samples: [Float]) {
            incoming += samples
            while incoming.count >= Self.frame {
                let frame = Array(incoming.prefix(Self.frame))
                incoming.removeFirst(Self.frame)
                pending += frame
                silence = Self.decibels(frame) < Self.silenceDB ? silence + 0.1 : 0
                let seconds = Double(pending.count) / Double(Self.sampleRate)
                if (silence >= Self.pauseToCut && seconds >= Self.minChunk) || seconds >= Self.maxChunk {
                    // Cut in the middle of the pause.
                    let cut = pending.count - Int(silence / 2 * Double(Self.sampleRate))
                    let chunk = Array(pending.prefix(cut))
                    pending.removeFirst(cut)
                    if Self.hasSpeech(chunk) { enqueue(chunk) }
                }
            }
        }

        private func enqueue(_ chunk: [Float]) {
            let previous = last
            last = Task {
                var parts = try await previous?.value ?? []
                // The first chunk settles the language; later chunks reuse it.
                let fixed = queue.sync { language }
                let result = try await engine.transcribe(chunk, language: fixed)
                queue.sync { if language == nil { language = result.language } }
                parts.append(result.text)
                return parts
            }
        }

        private static func decibels(_ samples: [Float]) -> Float {
            guard !samples.isEmpty else { return -160 }
            let power = samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count)
            return 10 * log10(max(power, 1e-16))
        }

        private static func hasSpeech(_ samples: [Float]) -> Bool {
            stride(from: 0, to: max(0, samples.count - 480), by: 480).contains { start in
                decibels(Array(samples[start..<start + 480])) > silenceDB
            }
        }
    }
}
