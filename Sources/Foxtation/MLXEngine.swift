import Foundation

/// Drives the persistent Python worker that runs mlx-whisper on the Apple GPU.
///
/// Keeping one worker alive is the whole point: loading the model takes 4–5 s,
/// while transcribing a short utterance from a warm model takes ~3 s. A fresh
/// process per dictation would pay the load cost every single time.
final class MLXEngine {

    struct Response {
        var text: String
        var language: String
        var elapsed: Double
    }

    enum EngineError: LocalizedError {
        case runtimeMissing
        case scriptMissing
        case startup(String)
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .runtimeMissing:
                return "MLX runtime is not installed — open Settings › Engine and press “Set Up”."
            case .scriptMissing:
                return "mlx_worker.py is missing from the app bundle."
            case .startup(let detail):
                return "MLX worker failed to start: \(detail)"
            case .failed(let detail):
                return "MLX transcription failed: \(detail)"
            }
        }
    }

    static let shared = MLXEngine()

    /// Terminate the worker after this long without use to give the ~1.6 GB
    /// of model weights back to the system.
    var idleTimeout: TimeInterval = 15 * 60

    private let queue = DispatchQueue(label: "com.khmuhtadin.foxtation.mlx", qos: .userInitiated)
    private let stateLock = NSLock()

    private var process: Process?
    private var input: FileHandle?
    private var outPipe: Pipe?
    private var errPipe: Pipe?
    private var lineBuffer = Data()
    private var stderrTail = ""
    private var repo: String?
    private var isReady = false
    private var startupWaiters: [(Result<Void, Error>) -> Void] = []
    private var requestWaiter: ((Result<Response, Error>) -> Void)?
    private var idleTimer: Timer?

    /// Fired on the main thread when the model has finished loading or has been unloaded.
    var onStateChange: ((String) -> Void)?

    private init() {}

    // MARK: - Public API

    var loadedRepository: String? {
        stateLock.lock(); defer { stateLock.unlock() }
        return isReady ? repo : nil
    }

    /// Loads the model if it is not already resident, then transcribes.
    func transcribe(audio: URL,
                    repo: String,
                    language: String,
                    translate: Bool,
                    prompt: String?) async throws -> Response {
        cancelIdleUnload()
        try await ensureStarted(repo: repo)
        defer { scheduleIdleUnload() }

        let request: [String: Any] = [
            "audio": audio.path,
            "language": language,
            "task": translate ? "translate" : "transcribe",
            "prompt": prompt ?? "",
        ]
        return try await send(request)
    }

    /// Preloads the model so the next dictation is instant.
    func preload(repo: String) {
        Task {
            try? await ensureStarted(repo: repo)
            scheduleIdleUnload()
        }
    }

    func unload() {
        queue.async { self.stopLocked(reason: nil) }
    }

    // MARK: - Lifecycle

    private func ensureStarted(repo: String) async throws -> Void {
        if let current = loadedRepository, current == repo { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            queue.async {
                if self.isReady, self.repo == repo {
                    continuation.resume()
                    return
                }
                // Switching models fails anyone still waiting on the old one,
                // so stop before registering this waiter.
                if self.process != nil, self.repo != repo {
                    self.stopLocked(reason: nil)
                }
                self.startupWaiters.append { result in
                    continuation.resume(with: result)
                }
                if self.process == nil {
                    self.startLocked(repo: repo)
                }
            }
        }
    }

    private func startLocked(repo: String) {
        guard let runtime = MLXRuntime.shared.readyPython() else {
            flushStartup(.failure(EngineError.runtimeMissing))
            return
        }
        guard let script = Self.workerScriptURL() else {
            flushStartup(.failure(EngineError.scriptMissing))
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: runtime)
        process.arguments = [script.path, repo]
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        environment["HF_HUB_DISABLE_PROGRESS_BARS"] = "1"
        process.environment = environment

        self.process = process
        self.outPipe = outPipe
        self.errPipe = errPipe
        setReady(false, repo: repo)
        self.lineBuffer.removeAll()
        self.stderrTail = ""

        // On EOF the handler fires forever with empty data unless cleared.
        // Chunks from a worker that has since been replaced are dropped.
        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            self?.queue.async {
                guard let self, self.process === process else { return }
                self.ingest(chunk)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            if chunk.isEmpty { handle.readabilityHandler = nil; return }
            guard let text = String(data: chunk, encoding: .utf8) else { return }
            self?.queue.async {
                guard let self, self.process === process else { return }
                self.appendStderr(text)
            }
        }

        process.terminationHandler = { [weak self] proc in
            self?.queue.async {
                guard let self, self.process === proc else { return }
                self.handleTermination(status: proc.terminationStatus)
            }
        }

        do {
            try process.run()
            self.input = (process.standardInput as? Pipe)?.fileHandleForWriting
            DispatchQueue.main.async { self.onStateChange?("Loading \(repo)…") }
        } catch {
            self.process = nil
            flushStartup(.failure(EngineError.startup(error.localizedDescription)))
        }
    }

    private func stopLocked(reason: Error?) {
        let proc = process
        let oldInput = input
        clearPipes()
        process = nil
        input = nil
        setReady(false, repo: nil)
        lineBuffer.removeAll()
        cancelIdleUnload()

        if let proc, proc.isRunning {
            proc.terminationHandler = nil
            try? oldInput?.close()
            proc.terminate()
        }

        // Anyone still waiting on this worker must hear back, or they hang forever.
        let error = reason ?? EngineError.failed("model unloaded")
        flushStartup(.failure(error))
        failRequest(error)
        if reason == nil {
            DispatchQueue.main.async { self.onStateChange?("Model unloaded") }
        }
    }

    private func clearPipes() {
        outPipe?.fileHandleForReading.readabilityHandler = nil
        errPipe?.fileHandleForReading.readabilityHandler = nil
        outPipe = nil
        errPipe = nil
    }

    private func setReady(_ ready: Bool, repo: String?) {
        stateLock.lock()
        isReady = ready
        self.repo = repo
        stateLock.unlock()
    }

    private func handleTermination(status: Int32) {
        let wasReady = isReady
        let detail = stderrTail.isEmpty ? "worker exited with code \(status)" : String(stderrTail.suffix(400))
        clearPipes()
        process = nil
        input = nil
        setReady(false, repo: nil)

        if !wasReady {
            flushStartup(.failure(EngineError.startup(detail)))
        }
        failRequest(EngineError.failed(detail))
    }

    private func flushStartup(_ result: Result<Void, Error>) {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters { waiter(result) }
    }

    private func failRequest(_ error: Error) {
        guard let waiter = requestWaiter else { return }
        requestWaiter = nil
        waiter(.failure(error))
    }

    // MARK: - Protocol

    private func send(_ request: [String: Any]) async throws -> Response {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Response, Error>) in
            queue.async {
                guard self.isReady, let input = self.input else {
                    continuation.resume(throwing: EngineError.runtimeMissing)
                    return
                }
                // One request at a time: an abandoned earlier request must not
                // receive (or steal) this one's response.
                self.failRequest(EngineError.failed("superseded by a newer request"))
                self.requestWaiter = { result in
                    continuation.resume(with: result)
                }
                do {
                    var data = try JSONSerialization.data(withJSONObject: request, options: [])
                    data.append(0x0A)
                    try input.write(contentsOf: data)
                } catch {
                    self.requestWaiter = nil
                    continuation.resume(throwing: EngineError.failed(error.localizedDescription))
                }
            }
        }
    }

    private func ingest(_ chunk: Data) {
        lineBuffer.append(chunk)
        while let index = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[lineBuffer.startIndex..<index]
            lineBuffer.removeSubrange(lineBuffer.startIndex...index)
            guard let line = String(data: lineData, encoding: .utf8), !line.isEmpty else { continue }
            handle(line: line)
        }
    }

    private func handle(line: String) {
        guard let data = line.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }

        if let ready = payload["ready"] as? Bool {
            if ready {
                setReady(true, repo: repo)
                let seconds = payload["load_seconds"] as? Double ?? 0
                DispatchQueue.main.async {
                    self.onStateChange?(String(format: "Model ready in %.1fs", seconds))
                }
                flushStartup(.success(()))
            } else {
                let message = payload["error"] as? String ?? "unknown error"
                flushStartup(.failure(EngineError.startup(message)))
            }
            return
        }

        guard let waiter = requestWaiter else { return }
        requestWaiter = nil

        if let ok = payload["ok"] as? Bool, ok {
            waiter(.success(Response(text: payload["text"] as? String ?? "",
                                     language: payload["language"] as? String ?? "auto",
                                     elapsed: payload["elapsed"] as? Double ?? 0)))
        } else {
            waiter(.failure(EngineError.failed(payload["error"] as? String ?? "unknown error")))
        }
    }

    private func appendStderr(_ text: String) {
        stderrTail += text
        if stderrTail.count > 8_000 {
            stderrTail = String(stderrTail.suffix(4_000))
        }
    }

    // MARK: - Idle unload

    /// With "keep model loaded" on, the worker stays resident; otherwise it is
    /// released after `idleTimeout` without use.
    private func scheduleIdleUnload() {
        DispatchQueue.main.async {
            self.idleTimer?.invalidate()
            self.idleTimer = nil
            guard !Settings.shared.keepModelLoaded else { return }
            self.idleTimer = Timer.scheduledTimer(withTimeInterval: self.idleTimeout, repeats: false) { _ in
                self.unload()
            }
        }
    }

    private func cancelIdleUnload() {
        DispatchQueue.main.async {
            self.idleTimer?.invalidate()
            self.idleTimer = nil
        }
    }

    // MARK: - Worker script

    /// The worker lives either in the app bundle (shipped builds) or beside the
    /// sources (when running through `swift run`).
    static func workerScriptURL() -> URL? {
        var candidates: [URL] = []
        if let resource = Bundle.main.resourceURL {
            candidates.append(resource.appendingPathComponent("mlx_worker.py"))
        }
        candidates.append(Bundle.main.bundleURL.appendingPathComponent("mlx_worker.py"))
        candidates.append(Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/mlx_worker.py"))
        candidates.append(URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Resources/mlx_worker.py"))
        candidates.append(MLXRuntime.shared.workerScriptPath)

        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }
}
