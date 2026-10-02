import Foundation

struct Transcript {
    var text: String
    var language: String
    var duration: Double
}

enum TranscriberError: LocalizedError {
    case binaryNotFound(String)
    case modelMissing(String)
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let p):
            return "whisper.cpp CLI not found at \(p.isEmpty ? "default locations" : p).\nInstall it with:  brew install whisper-cpp"
        case .modelMissing(let p):
            return "Model file not found: \(p)"
        case .failed(let m):
            return m
        }
    }
}

/// Thin wrapper around the `whisper-cli` executable. Text is read back from a
/// temp `.txt` file rather than stdout, because whisper.cpp mixes progress and
/// system info into stdout/stderr unpredictably.
enum Transcriber {

    static let binaryCandidates = [
        "/opt/homebrew/bin/whisper-cli",
        "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp",
        "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/bin/main",
    ]

    static func resolveBinary(configured: String) -> String? {
        if !configured.isEmpty, FileManager.default.isExecutableFile(atPath: configured) {
            return configured
        }
        return binaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func transcribe(audio: URL, settings: Settings) async throws -> Transcript {
        guard let binary = resolveBinary(configured: settings.whisperBinary) else {
            throw TranscriberError.binaryNotFound(settings.whisperBinary)
        }
        let model = settings.modelPath
        guard !model.isEmpty, FileManager.default.fileExists(atPath: model) else {
            throw TranscriberError.modelMissing(model.isEmpty ? "(no model selected)" : model)
        }

        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("Foxtation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }

        let stem = work.appendingPathComponent("out")
        var args = [
            "-m", model,
            "-f", audio.path,
            "-l", settings.language,
            "-t", String(settings.threads),
            "-nt",                    // no timestamps — we want plain prose
            "-np",                    // keep stdout clean
            "-otxt",
            "-of", stem.path,
        ]
        if settings.translate { args.append("-tr") }
        if !settings.initialPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            args.append(contentsOf: ["--prompt", settings.initialPrompt])
        }

        let result = try await run(binary: binary, args: args)
        guard result.status == 0 else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw TranscriberError.failed(detail.isEmpty ? "whisper.cpp exited with code \(result.status)" : detail)
        }

        let textFile = URL(fileURLWithPath: stem.path + ".txt")
        guard let raw = try? String(contentsOf: textFile, encoding: .utf8) else {
            throw TranscriberError.failed("whisper.cpp produced no transcript.")
        }

        let text = clean(raw)
        guard !text.isEmpty else { throw TranscriberError.failed("No speech detected.") }

        let detected = detectLanguage(from: result.stderr) ?? settings.language
        return Transcript(text: text, language: detected, duration: result.seconds)
    }

    // MARK: - Process

    private struct RunResult {
        var status: Int32
        var stderr: String
        var seconds: Double
    }

    private static func run(binary: String, args: [String]) async throws -> RunResult {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: binary)
                process.arguments = args
                process.standardInput = FileHandle.nullDevice

                // whisper.cpp prints its banner to stderr; keep the pipe small
                // by draining it on a background queue as it arrives.
                let errPipe = Pipe()
                process.standardError = errPipe
                process.standardOutput = FileHandle.nullDevice

                var collected = Data()
                let lock = NSLock()
                errPipe.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    guard !chunk.isEmpty else { return }
                    lock.lock(); collected.append(chunk); lock.unlock()
                }

                let started = Date()
                do {
                    try process.run()
                } catch {
                    errPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: TranscriberError.failed(error.localizedDescription))
                    return
                }

                // Hard ceiling so a hung model can never wedge the app.
                let deadline = Date().addingTimeInterval(600)
                while process.isRunning && Date() < deadline {
                    usleep(50_000)
                }
                if process.isRunning { process.terminate() }

                process.waitUntilExit()
                errPipe.fileHandleForReading.readabilityHandler = nil
                let tail = errPipe.fileHandleForReading.readDataToEndOfFile()
                lock.lock(); collected.append(tail); let data = collected; lock.unlock()

                continuation.resume(returning: RunResult(
                    status: process.terminationStatus,
                    stderr: String(data: data, encoding: .utf8) ?? "",
                    seconds: Date().timeIntervalSince(started)
                ))
            }
        }
    }

    // MARK: - Post-processing

    private static func clean(_ raw: String) -> String {
        raw.split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func detectLanguage(from stderr: String) -> String? {
        guard let range = stderr.range(of: "auto-detected language: ") else { return nil }
        let rest = stderr[range.upperBound...]
        guard let end = rest.firstIndex(of: " ") ?? rest.firstIndex(of: "\n") else {
            return String(rest).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return String(rest[..<end])
    }
}
