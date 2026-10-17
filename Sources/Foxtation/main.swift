import AppKit
import Foundation

/// Headless mode: `Foxtation --transcribe file.wav` prints the transcript and
/// exits. Useful for scripting and for verifying the engine without the UI.
func runHeadlessIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard let flagIndex = arguments.firstIndex(of: "--transcribe") else { return false }
    guard flagIndex + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: Foxtation --transcribe file.wav [--engine mlx|cpp] [--model M] [--language L] [--translate] [--prompt P] [--cleanup [--app BUNDLE_ID] [--sample-library]]\n".utf8))
        exit(2)
    }
    let audio = URL(fileURLWithPath: arguments[flagIndex + 1])
    guard FileManager.default.fileExists(atPath: audio.path) else {
        FileHandle.standardError.write(Data("error: no such file: \(audio.path)\n".utf8))
        exit(2)
    }

    func value(for key: String) -> String? {
        guard let index = arguments.firstIndex(of: key), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    // CLI flags apply to this run only; never write them into the app's preferences.
    let settings = Settings.shared
    settings.persistsChanges = false
    if let engine = value(for: "--engine") {
        settings.engine = engine == "cpp" ? .whisperCpp : engine == "wk" ? .whisperKit : .mlx
    }
    if let model = value(for: "--model") {
        if settings.engine == .mlx { settings.mlxModel = model } else { settings.modelPath = model }
    }
    if let language = value(for: "--language") { settings.language = language }
    if arguments.contains("--translate") { settings.translate = true }
    if let prompt = value(for: "--prompt") { settings.initialPrompt = prompt }

    let semaphore = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    Task {
        do {
            let started = Date()
            let transcript: Transcript
            switch settings.engine {
            case .mlx:
                let response = try await MLXEngine.shared.transcribe(
                    audio: audio,
                    repo: settings.mlxModel,
                    language: settings.language,
                    translate: settings.translate,
                    prompt: settings.initialPrompt)
                transcript = Transcript(text: response.text,
                                        language: response.language,
                                        duration: response.elapsed)
            case .whisperCpp:
                transcript = try await Transcriber.transcribe(audio: audio, settings: settings)
            case .whisperKit:
                let samples = try WhisperKitEngine.samples(of: audio)
                if arguments.contains("--realtime") {
                    transcript = try await transcribeInRealTime(samples, language: settings.language)
                } else {
                    let result = try await WhisperKitEngine.shared.transcribe(
                        samples, language: settings.language == "auto" ? nil : settings.language)
                    transcript = Transcript(text: result.text, language: result.language, duration: 0)
                }
            }
            let wall = Date().timeIntervalSince(started)
            if arguments.contains("--cleanup") {
                try await printCleanup(of: transcript, settings: settings,
                                       bundleID: value(for: "--app") ?? "",
                                       library: arguments.contains("--sample-library") ? .sample() : Library.shared.inMemoryCopy())
            } else {
                print(transcript.text)
            }
            FileHandle.standardError.write(Data(String(
                format: "engine=%@ language=%@ wall=%.2fs\n",
                settings.engine == .mlx ? settings.mlxModel : settings.engine == .whisperKit ? "whisperkit" : "whisper.cpp",
                transcript.language, wall).utf8))
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exitCode = 1
        }
        semaphore.signal()
    }

    while semaphore.wait(timeout: .now()) == .timedOut {
        RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
    }
    exit(exitCode)
}

/// `--realtime` (WhisperKit): feeds the clip at 1× speed in 100 ms buffers, as the
/// recorder would, then "releases" and reports how long the text took after that.
func transcribeInRealTime(_ samples: [Float], language: String) async throws -> Transcript {
    _ = try await WhisperKitEngine.shared.load()
    let session = WhisperKitEngine.Session(language: language)
    let step = 1_600
    let start = Date()
    for offset in stride(from: 0, to: samples.count, by: step) {
        session.append(Array(samples[offset..<min(offset + step, samples.count)]))
        let due = start.addingTimeInterval(Double(offset + step) / 16_000)
        let wait = due.timeIntervalSinceNow
        if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
    }
    let transcript = try await session.finish()
    FileHandle.standardError.write(Data(String(format: "release→text=%.2fs\n", transcript.duration).utf8))
    return transcript
}

/// `--cleanup`: runs the same pipeline as a real dictation into `bundleID`,
/// cloud cleanup included, and prints every stage instead of pasting.
func printCleanup(of raw: Transcript, settings: Settings, bundleID: String, library: Library) async throws {
    let name = library.groups.values.flatMap(\.apps).first { $0.bundleID == bundleID }?.name ?? bundleID
    let target = DictationTarget(name: name, bundleID: bundleID)
    let request = DictationPipeline.request(for: raw, target: target, settings: settings, library: library)
    let started = Date()
    let cleaned = await DictationPipeline.cleanUp(raw, request: request,
                                                  licenseKey: settings.licenseKey, activationID: settings.activationID)
    FileHandle.standardError.write(Data(String(format: "cleanup=%.2fs\n", Date().timeIntervalSince(started)).utf8))
    print("raw:     \(raw.text)")
    print("style:   \(request?.style?.rawValue ?? "-") (app: \(request?.app ?? "-"))")
    if let fallback = cleaned.fallback {
        print("cloud:   FALLBACK \(fallback)")
    } else if cleaned.cloud {
        print("cloud:   \(cleaned.text)")
    } else {
        print("cloud:   off (cleanup disabled or not activated)")
    }
    print("final:   \(DictationPipeline.finish(cleaned.text, target: target, library: library))")
    if let changes = cleaned.changes {
        print("changes: fillers \(changes.fillersRemoved), self-corrections \(changes.selfCorrections), formatting \(changes.formattingFixes)")
    }
    if let usage = cleaned.usage { print("usage:   \(usage.used)/\(usage.limit)") }
}

// Writing to a dead worker's stdin must surface as an error, not kill the app.
signal(SIGPIPE, SIG_IGN)

// Hidden: `Foxtation --render-hud <dir>` writes HUD screenshots and exits.
if let index = CommandLine.arguments.firstIndex(of: "--render-hud"), index + 1 < CommandLine.arguments.count {
    _ = NSApplication.shared
    MainActor.assumeIsolated {
        do {
            try HUDSnapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

// Hidden: `Foxtation --render-window <dir> [filter]` writes main window screenshots and exits.
if let index = CommandLine.arguments.firstIndex(of: "--render-window"), index + 1 < CommandLine.arguments.count {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let filter = index + 2 < CommandLine.arguments.count ? CommandLine.arguments[index + 2] : nil
    MainActor.assumeIsolated {
        do {
            try WindowSnapshots.render(to: URL(fileURLWithPath: CommandLine.arguments[index + 1]), filter: filter)
            exit(0)
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

// Hidden: `Foxtation --ui-test [--dump]` clicks through the window with throwaway data and exits.
if CommandLine.arguments.contains("--ui-test") {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    MainActor.assumeIsolated {
        exit(UITest.run(dump: CommandLine.arguments.contains("--dump")))
    }
}

if !runHeadlessIfRequested() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
