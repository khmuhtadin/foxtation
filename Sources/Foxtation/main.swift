import AppKit
import Foundation

/// Headless mode: `Foxtation --transcribe file.wav` prints the transcript and
/// exits. Useful for scripting and for verifying the engine without the UI.
func runHeadlessIfRequested() -> Bool {
    let arguments = CommandLine.arguments
    guard let flagIndex = arguments.firstIndex(of: "--transcribe") else { return false }
    guard flagIndex + 1 < arguments.count else {
        FileHandle.standardError.write(Data("usage: Foxtation --transcribe file.wav [--engine mlx|cpp] [--model M] [--language L] [--translate] [--prompt P]\n".utf8))
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
        settings.engine = engine == "cpp" ? .whisperCpp : .mlx
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
            }
            let wall = Date().timeIntervalSince(started)
            print(transcript.text)
            FileHandle.standardError.write(Data(String(
                format: "engine=%@ language=%@ wall=%.2fs\n",
                settings.engine == .mlx ? settings.mlxModel : "whisper.cpp",
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

if !runHeadlessIfRequested() {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
