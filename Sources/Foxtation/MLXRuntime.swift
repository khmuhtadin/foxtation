import Foundation

struct MLXModel: Hashable {
    var name: String
    var repo: String
    var size: String
    var note: String
    var recommended: Bool = false
}

/// Owns the Python side of the MLX engine: a private virtualenv with
/// `mlx-whisper` installed, plus the Hugging Face model cache.
final class MLXRuntime {

    static let shared = MLXRuntime()

    static let catalog: [MLXModel] = [
        MLXModel(name: "Large v3 Turbo (4-bit)", repo: "mlx-community/whisper-large-v3-turbo-q4",
                 size: "0.46 GB", note: "Quantized — fastest, lowest memory"),
        MLXModel(name: "Large v3 Turbo", repo: "mlx-community/whisper-large-v3-turbo",
                 size: "1.6 GB", note: "Full precision — best accuracy", recommended: true),
        MLXModel(name: "Small", repo: "mlx-community/whisper-small-mlx",
                 size: "0.48 GB", note: "Good balance"),
        MLXModel(name: "Base", repo: "mlx-community/whisper-base-mlx",
                 size: "0.15 GB", note: "Quick, decent for clear speech"),
        MLXModel(name: "Tiny", repo: "mlx-community/whisper-tiny-mlx",
                 size: "0.08 GB", note: "Fastest, lowest accuracy"),
    ]

    /// Fired on the main thread with a human-readable status line.
    var onStatus: ((String) -> Void)?
    /// Fired on the main thread when provisioning or a download finishes.
    var onFinished: (() -> Void)?
    /// Fired on the main thread when something fails.
    var onError: ((String) -> Void)?
    /// Fired on the main thread whenever any of the above changes state.
    var onChange: (() -> Void)?

    private(set) var isBusy = false
    private(set) var busyLabel = ""

    private let root: URL
    private let lock = NSLock()
    private var cachedPython: String??

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        root = support.appendingPathComponent("Foxtation/mlx", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var venvDirectory: URL { root.appendingPathComponent("venv", isDirectory: true) }
    var pythonPath: String { venvDirectory.appendingPathComponent("bin/python").path }
    var cliPath: String { venvDirectory.appendingPathComponent("bin/mlx_whisper").path }
    var workerScriptPath: URL { root.appendingPathComponent("mlx_worker.py") }

    /// Copies the bundled worker next to the venv so the app keeps working even
    /// if it is later launched from somewhere else.
    func installWorkerScript() {
        guard let source = MLXEngine.workerScriptURL() else { return }
        guard source.path != workerScriptPath.path else { return }
        try? FileManager.default.removeItem(at: workerScriptPath)
        try? FileManager.default.copyItem(at: source, to: workerScriptPath)
    }

    // MARK: - Readiness

    /// Returns the venv python when mlx-whisper is importable, otherwise nil.
    /// Cached because the probe costs ~1 s of interpreter start-up.
    func readyPython(refresh: Bool = false) -> String? {
        lock.lock()
        if !refresh, let cachedPython { lock.unlock(); return cachedPython }
        lock.unlock()

        guard FileManager.default.isExecutableFile(atPath: pythonPath) else {
            lock.lock(); cachedPython = .some(nil); lock.unlock()
            return nil
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: pythonPath)
        process.arguments = ["-c", "import mlx_whisper"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return nil }
        process.waitUntilExit()
        let ok = process.terminationStatus == 0 ? pythonPath : nil

        lock.lock(); cachedPython = .some(ok); lock.unlock()
        return ok
    }

    func invalidateReadiness() {
        lock.lock(); cachedPython = nil; lock.unlock()
    }

    // MARK: - Model cache

    private var hubCache: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub", isDirectory: true)
    }

    func isModelDownloaded(_ model: MLXModel) -> Bool {
        let folder = "models--" + model.repo.replacingOccurrences(of: "/", with: "--")
        return FileManager.default.fileExists(atPath: hubCache.appendingPathComponent(folder).path)
    }

    func deleteModel(_ model: MLXModel) {
        let folder = "models--" + model.repo.replacingOccurrences(of: "/", with: "--")
        try? FileManager.default.removeItem(at: hubCache.appendingPathComponent(folder))
        DispatchQueue.main.async { self.onChange?() }
    }

    // MARK: - Provisioning

    /// Creates the venv and installs mlx-whisper. Runs on a background queue and
    /// reports progress through `onStatus`.
    func provision() {
        guard begin(label: "Setting up MLX runtime…") else { return }

        let uv = ProcessRunner.locate("uv", extra: [Settings.shared.uvPath])
        guard let uv else {
            finish(error: "`uv` not found. Install it with:  brew install uv")
            return
        }

        Task {
            do {
                if !FileManager.default.isExecutableFile(atPath: pythonPath) {
                    report("Creating virtual environment…")
                    let create = try await ProcessRunner.run(
                        executable: uv,
                        arguments: ["venv", "--python", "3.12", venvDirectory.path],
                        timeout: 600,
                        onLine: { self.report($0) })
                    guard create.status == 0 else {
                        finish(error: "uv venv failed: \(tail(create.combined))")
                        return
                    }
                }

                report("Installing mlx-whisper (this downloads ~200 MB of wheels)…")
                let install = try await ProcessRunner.run(
                    executable: uv,
                    arguments: ["pip", "install", "--python", pythonPath, "--upgrade", "mlx-whisper"],
                    timeout: 1800,
                    onLine: { self.report($0) })
                guard install.status == 0 else {
                    finish(error: "uv pip install failed: \(tail(install.combined))")
                    return
                }

                invalidateReadiness()
                finish(error: nil)
            } catch {
                finish(error: error.localizedDescription)
            }
        }
    }

    /// Pre-downloads a model into the Hugging Face cache so the first
    /// dictation is not blocked by a multi-gigabyte fetch.
    func downloadModel(_ model: MLXModel) {
        guard let python = readyPython() else {
            // Not `finish`: that would clear the busy flag of an operation we never began.
            DispatchQueue.main.async { self.onError?("MLX runtime is not installed yet.") }
            return
        }
        guard begin(label: "Downloading \(model.name)…") else { return }

        Task {
            do {
                let script = "from huggingface_hub import snapshot_download; snapshot_download('\(model.repo)')"
                let result = try await ProcessRunner.run(
                    executable: python,
                    arguments: ["-c", script],
                    environment: ["PYTHONUNBUFFERED": "1"],
                    timeout: 3600,
                    onLine: { self.report($0) })
                if result.status != 0 {
                    finish(error: "Download failed: \(tail(result.combined))")
                } else {
                    finish(error: nil)
                }
            } catch {
                finish(error: error.localizedDescription)
            }
        }
    }

    // MARK: - Bookkeeping

    private func begin(label: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !isBusy else { return false }
        isBusy = true
        busyLabel = label
        DispatchQueue.main.async {
            self.onStatus?(label)
            self.onChange?()
        }
        return true
    }

    private func report(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        DispatchQueue.main.async {
            self.busyLabel = trimmed
            self.onStatus?(trimmed)
            self.onChange?()
        }
    }

    private func finish(error: String?) {
        lock.lock(); isBusy = false; lock.unlock()
        DispatchQueue.main.async {
            if let error { self.onError?(error) } else { self.onFinished?() }
            self.onChange?()
        }
    }

    private func tail(_ text: String, lines: Int = 4) -> String {
        let all = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        return all.suffix(lines).joined(separator: " · ")
    }
}
