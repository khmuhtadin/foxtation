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
        /// The full tokenizer; `kit.tokenizer` may be a copy that detects fewer languages.
        private let tokenizer: WhisperTokenizer?
        private var detecting: [String] = []

        init(_ kit: WhisperKit) {
            self.kit = kit
            tokenizer = kit.tokenizer
        }

        /// Makes language detection pick only from `languages` (empty: any of
        /// Whisper's 99). Left to choose from all of them, a few seconds of
        /// Indonesian come out as Malay, Tagalog or even Korean.
        func detect(among languages: [String]) {
            guard languages != detecting, let tokenizer, let old = kit.textDecoder as? TextDecoder else { return }
            detecting = languages
            // WhisperKit builds its language filter once per text decoder, so
            // swap in a fresh decoder on the same Core ML model.
            let fresh = TextDecoder()
            fresh.model = old.model
            fresh.isModelMultilingual = old.isModelMultilingual
            fresh.logitsFilters = old.logitsFilters
            kit.textDecoder = fresh
            kit.tokenizer = languages.isEmpty ? tokenizer : DetectionTokenizer(tokenizer, languages: languages)
        }
    }

    /// Whisper's tokenizer, except that only `languages` count as language tokens.
    private final class DetectionTokenizer: WhisperTokenizer {
        let base: WhisperTokenizer
        let allLanguageTokens: Set<Int>

        init(_ base: WhisperTokenizer, languages: [String]) {
            self.base = base
            allLanguageTokens = Set(languages.compactMap { base.convertTokenToId("<|\($0)|>") })
        }

        var specialTokens: SpecialTokens { base.specialTokens }
        func encode(text: String) -> [Int] { base.encode(text: text) }
        func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
        func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
        func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
        func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
            base.splitToWordTokens(tokenIds: tokenIds)
        }
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

    /// The model's size on disk (1.6 GB), for the download progress.
    static let downloadBytes = 1_638_464_446

    /// Written once every file is downloaded, so a download that was cut off
    /// halfway doesn't count as installed.
    private static var completeMarker: URL { modelFolder.appendingPathComponent(".foxtation-complete") }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: Self.completeMarker.path)
    }

    // MARK: - Setup

    /// Downloads the model if needed, then loads it.
    func install() {
        guard !isInstalled else { prewarm(); return }
        Task {
            state = .downloading(0)
            // WhisperKit's own progress counts files, not bytes, so it would sit
            // still during the one 1.3 GB file. Count the bytes on disk instead.
            let progress = Task {
                while !Task.isCancelled {
                    state = .downloading(min(0.99, Double(Self.bytesOnDisk()) / Double(Self.downloadBytes)))
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            do {
                _ = try await WhisperKit.download(variant: Self.modelName, downloadBase: Self.downloadBase)
                progress.cancel()
                await progress.value
                FileManager.default.createFile(atPath: Self.completeMarker.path, contents: nil)
                _ = try await load()
            } catch {
                progress.cancel()
                await progress.value
                state = .failed(error.localizedDescription)
            }
        }
    }

    /// Everything under the download folder, partly downloaded files included.
    private static func bytesOnDisk() -> Int {
        let files = FileManager.default.enumerator(at: downloadBase, includingPropertiesForKeys: [.fileSizeKey])
        var total = 0
        while let file = files?.nextObject() as? URL {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
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

    /// `language` nil detects it, choosing only from `languages` (empty: any).
    /// Returns the text and the language used.
    func transcribe(_ samples: [Float], language: String?, among languages: [String] = []) async throws -> (text: String, language: String) {
        let model = try await load()
        model.detect(among: languages)
        let kit = model.kit
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

    /// A dictation transcribed on this Mac while you speak. `language` "auto"
    /// detects it per chunk among `languages`.
    func session(language: String, among languages: [String]) -> SpeechSession {
        let pinned = language == "auto" ? nil : language
        return SpeechSession { [self] chunk in
            try await transcribe(chunk, language: pinned, among: languages)
        }
    }
}
