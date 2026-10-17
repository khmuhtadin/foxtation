import AppKit
import AVFoundation
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {

    enum Phase {
        case idle, recording, transcribing
    }

    private let settings = Settings.shared
    private let recorder = Recorder()
    private let hud = HUD()
    private var statusItem: NSStatusItem?
    private var hotKey: HotKey?
    private let history = History.shared
    private let library = Library.shared
    private let cloud = CloudStatus.shared
    private lazy var mainWindow = MainWindowController(model: makeAppModel())
    private var phase: Phase = .idle
    private var currentCapture: URL?
    private var lastTranscript: String?
    /// WhisperKit: transcribes while the user is still speaking.
    private var stream: SpeechSession?
    /// The app the user is dictating into, captured when recording starts.
    private var target = DictationTarget(name: "", bundleID: "")
    /// Bumped on every finish/cancel so a stale transcription result is dropped.
    private var session = 0
    private var registeredHotKey: (code: UInt32, modifiers: UInt32)?
    private var appliedLaunchAtLogin: Bool?
    private var askedForAccessibility = false

    // Right ⌥: hold to talk; double-tap for hands-free, tap again to stop.
    private let rightOption = RightOptionKey()
    private var handsFree = false
    private var ignoreRelease = false
    private var pressedAt = Date.distantPast
    private var lastTapAt = Date.distantPast

    private let audioDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("Foxtation", isDirectory: true)

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        settings.onChange = { [weak self] in self?.applySettings() }
        history.prune(settings.historyRetention)
        Task { await cloud.refresh() }
        installEditMenu()
        installStatusItem()
        wireRecorder()
        hud.onCancel = { [weak self] in self?.cancelTranscription() }
        registerHotKey()
        rightOption.onPress = { [weak self] in self?.rightOptionPressed() }
        rightOption.onRelease = { [weak self] in self?.rightOptionReleased() }
        rightOption.onChord = { [weak self] in self?.rightOptionChorded() }
        applyRightOption()

        Permissions.requestMicrophone { _ in }

        if settings.modelPath.isEmpty {
            settings.modelPath = Self.discoverModels().first?.path ?? ""
        }

        MLXEngine.shared.onStateChange = { [weak self] message in
            NSLog("Foxtation: %@", message)
            self?.refreshStatusItem()
        }
        MLXRuntime.shared.installWorkerScript()
        if settings.engine == .whisperKit { WhisperKitEngine.shared.prewarm() }
        if settings.engine == .mlx, settings.keepModelLoaded, MLXRuntime.shared.readyPython() != nil {
            MLXEngine.shared.preload(repo: settings.mlxModel)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.refreshStatusItem()
            self.showStartupGuidanceIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        recorder.cancel()
    }

    /// Opening Foxtation again (Finder, Spotlight, `open`) shows the main window.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        mainWindow.show()
        return false
    }

    /// No Dock icon; the menu bar item is the only surface.
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    // MARK: - Hot key

    /// Re-registers only when the combination changed. If the new one can't be
    /// registered (taken by another app), the previous shortcut stays active.
    private func registerHotKey() {
        let code = settings.hotKeyCode
        let modifiers = settings.hotKeyModifiers
        if let current = registeredHotKey, current.code == code, current.modifiers == modifiers, hotKey != nil {
            return
        }

        let previous = registeredHotKey
        hotKey = nil  // unregister first so re-registering a combination can't collide with itself
        hotKey = HotKey.register(keyCode: code,
                                 modifiers: modifiers,
                                 onPress: { [weak self] in self?.hotKeyPressed() },
                                 onRelease: { [weak self] in self?.hotKeyReleased() })
        if hotKey != nil {
            registeredHotKey = (code, modifiers)
            return
        }

        NSLog("Foxtation: failed to register hot key %@", HotKey.describe(keyCode: code, modifiers: modifiers))
        hud.show(.error("Shortcut unavailable — pick another"))
        registeredHotKey = nil
        if let previous {
            settings.hotKeyCode = previous.code
            settings.hotKeyModifiers = previous.modifiers
            registerHotKey()
        }
    }

    private func hotKeyPressed() {
        switch settings.triggerMode {
        case .toggle:
            if phase == .idle { startRecording() } else { finishRecording() }
        case .hold:
            if phase == .idle { startRecording() }
        }
    }

    private func hotKeyReleased() {
        guard settings.triggerMode == .hold else { return }
        if phase == .recording { finishRecording() }
    }

    // MARK: - Right ⌥

    private func applyRightOption() {
        if settings.holdRightOption { rightOption.start() } else { rightOption.stop() }
    }

    private func rightOptionPressed() {
        ignoreRelease = false
        if handsFree {
            finishRecording()
            ignoreRelease = true
            return
        }
        guard phase == .idle else { return }
        pressedAt = Date()
        startRecording()
    }

    private func rightOptionReleased() {
        guard !ignoreRelease, !handsFree, phase == .recording else { return }
        let now = Date()
        if now.timeIntervalSince(pressedAt) >= 0.3 {
            finishRecording()
            return
        }
        // A quick tap. The second of two taps switches to hands-free;
        // a lone tap is dropped.
        if now.timeIntervalSince(lastTapAt) < 0.5 {
            lastTapAt = .distantPast
            handsFree = true
        } else {
            lastTapAt = now
            cancelTranscription()
        }
    }

    /// ⌥ + another key means the user is typing (é, ™, ⌥⌫…), not dictating.
    private func rightOptionChorded() {
        ignoreRelease = true
        if phase == .recording && !handsFree { cancelTranscription() }
    }

    // MARK: - Capture

    private func wireRecorder() {
        recorder.maxSeconds = settings.maxSeconds
        recorder.onLevel = { [weak self] level in
            self?.hud.updateLevel(level)
        }
        recorder.onAutoStop = { [weak self] in
            self?.finishRecording()
        }
    }

    private func startRecording() {
        guard phase == .idle else { return }

        guard Permissions.microphoneGranted else {
            Permissions.requestMicrophone { [weak self] granted in
                guard let self else { return }
                if granted {
                    self.startRecording()
                } else {
                    self.hud.show(.error("Microphone access denied — enable it in System Settings › Privacy & Security › Microphone"))
                    Permissions.openMicrophoneSettings()
                }
            }
            return
        }

        switch settings.engine {
        case .cloud:
            guard !settings.activationID.isEmpty else {
                hud.show(.error("Foxtation Cloud needs Foxtation Pro — activate your license"))
                showSettings(.license)
                return
            }
        case .whisperKit:
            guard WhisperKitEngine.shared.isInstalled else {
                hud.show(.error("Speech model not installed — open Settings › Engine"))
                showSettings(.engine)
                return
            }
        case .mlx:
            guard MLXRuntime.shared.readyPython() != nil else {
                hud.show(.error("MLX runtime not installed — open Settings › Engine and press Set Up"))
                showSettings(.engine)
                return
            }
            guard MLXEngine.workerScriptURL() != nil else {
                hud.show(.error("mlx_worker.py missing from the app bundle"))
                return
            }
        case .whisperCpp:
            guard Transcriber.resolveBinary(configured: settings.whisperBinary) != nil else {
                hud.show(.error("whisper.cpp not found — run: brew install whisper-cpp"))
                return
            }
            guard !settings.modelPath.isEmpty, FileManager.default.fileExists(atPath: settings.modelPath) else {
                hud.show(.error("No speech model selected — pick one in Settings › Engine"))
                showSettings(.engine)
                return
            }
        }

        wireRecorder()
        let front = NSWorkspace.shared.frontmostApplication
        target = DictationTarget(name: front?.localizedName ?? "", bundleID: front?.bundleIdentifier ?? "")
        if settings.engine == .whisperKit || settings.engine == .cloud {
            let stream = settings.engine == .cloud
                ? CloudCleanup.session(language: settings.language, among: settings.spokenLanguages,
                                       licenseKey: settings.licenseKey, activationID: settings.activationID)
                : WhisperKitEngine.shared.session(language: settings.language, among: settings.spokenLanguages)
            self.stream = stream
            recorder.onSamples = { stream.append($0) }
        } else {
            stream = nil
            recorder.onSamples = nil
        }
        // Open the TLS connection now, so the cloud doesn't pay for it after release.
        if (settings.cloudCleanup || settings.engine == .cloud), !settings.activationID.isEmpty { CloudCleanup.warmUp() }
        do {
            try recorder.start()
            phase = .recording
            if settings.playSounds { NSSound(named: "Tink")?.play() }
            if settings.showHUD { hud.show(.listening) }
            refreshStatusItem()
        } catch {
            phase = .idle
            hud.show(.error(error.localizedDescription))
            refreshStatusItem()
        }
    }

    private func finishRecording() {
        guard phase == .recording else { return }
        handsFree = false

        if settings.playSounds { NSSound(named: "Pop")?.play() }

        let capture: URL
        let seconds: Double
        do {
            let result = try recorder.stop(writingTo: audioDirectory)
            capture = result.url
            seconds = result.duration
        } catch {
            phase = .idle
            hud.show(.error(error.localizedDescription))
            refreshStatusItem()
            return
        }

        session += 1
        let mySession = session
        currentCapture = capture
        phase = .transcribing
        if settings.showHUD { hud.show(.working) }
        refreshStatusItem()

        let target = self.target
        let stream = self.stream
        self.stream = nil
        Task { [weak self] in
            guard let self else { return }
            defer { try? FileManager.default.removeItem(at: capture) }

            let raw: Transcript
            do {
                if let stream {
                    do {
                        raw = try await stream.finish()
                    } catch where self.settings.engine == .cloud && WhisperKitEngine.shared.isInstalled {
                        // Offline or over the day's limit: the model on this Mac has the same recording.
                        NSLog("Foxtation: cloud transcription failed, using this Mac: %@", error.localizedDescription)
                        raw = try await self.transcribe(audio: capture)
                    }
                } else {
                    raw = try await self.transcribe(audio: capture)
                }
            } catch {
                await MainActor.run {
                    guard self.session == mySession else { return }  // cancelled meanwhile
                    self.currentCapture = nil
                    self.phase = .idle
                    self.refreshStatusItem()
                    self.hud.show(.error(error.localizedDescription))
                }
                return
            }

            let request = await MainActor.run { () -> CleanupRequest? in
                let request = DictationPipeline.request(for: raw, target: target, settings: self.settings, library: self.library)
                if request != nil, self.session == mySession, self.settings.showHUD {
                    self.hud.show(.cleaning(app: target.name))
                }
                return request
            }
            let cleanup = await DictationPipeline.cleanUp(raw, request: request,
                                                          licenseKey: self.settings.licenseKey,
                                                          activationID: self.settings.activationID)
            await MainActor.run {
                guard self.session == mySession else { return }  // cancelled meanwhile
                self.currentCapture = nil
                self.phase = .idle
                guard !raw.text.isEmpty else {
                    self.refreshStatusItem()
                    self.hud.show(.error("No speech detected"))
                    return
                }
                if let usage = cleanup.usage { self.cloud.usage = usage }
                let text = DictationPipeline.finish(cleanup.text, target: target, library: self.library,
                                                    cloudStyled: cleanup.cloud)
                self.lastTranscript = text
                self.refreshStatusItem()
                // Undo only when the cloud changed the words, and keep the local steps.
                let undoText = cleanup.cloud && cleanup.text != raw.text
                    ? DictationPipeline.finish(raw.text, target: target, library: self.library.inMemoryCopy())
                    : nil
                self.deliver(text, undoText: undoText, fallback: cleanup.fallback)
                self.record(Dictation(date: Date(), app: target.name, bundleID: target.bundleID,
                                      raw: raw.text, text: text, seconds: seconds,
                                      cloud: cleanup.cloud,
                                      changes: cleanup.changes),
                            audio: capture)
            }
        }
    }

    private func cancelTranscription() {
        handsFree = false
        stream = nil
        recorder.onSamples = nil
        if phase == .recording {
            recorder.cancel()
            phase = .idle
        } else if phase == .transcribing {
            session += 1
            currentCapture = nil
            phase = .idle
        }
        hud.cancel()
        refreshStatusItem()
    }

    // MARK: - Delivery

    private func transcribe(audio: URL) async throws -> Transcript {
        switch settings.engine {
        case .cloud, .whisperKit:  // the cloud streams; this is its offline fallback
            let result = try await WhisperKitEngine.shared.transcribe(
                try WhisperKitEngine.samples(of: audio),
                language: settings.language == "auto" ? nil : settings.language,
                among: settings.spokenLanguages)
            return Transcript(text: result.text, language: result.language, duration: 0)
        case .mlx:
            let response = try await MLXEngine.shared.transcribe(
                audio: audio,
                repo: settings.mlxModel,
                language: settings.language,
                translate: settings.translate,
                prompt: settings.initialPrompt)
            return Transcript(text: response.text,
                              language: response.language,
                              duration: response.elapsed)
        case .whisperCpp:
            return try await Transcriber.transcribe(audio: audio, settings: settings)
        }
    }

    private func deliver(_ text: String, undoText: String?, fallback: String?) {
        let outcome = Inserter.insert(text,
                                      method: settings.insertMethod,
                                      restoreClipboard: settings.restoreClipboard)

        switch outcome {
        case .inserted:
            guard settings.showHUD else { break }
            if let fallback {
                hud.show(.fallback(fallback))
            } else {
                let undo: (() -> Void)? = undoText.map { original in { [weak self] in self?.undoPaste(original) } }
                hud.show(.pasted(words: Dictation.wordCount(text), undo: undo))
            }
        case .copiedOnly:
            hud.show(.error("Copied to clipboard — grant Accessibility to insert automatically"))
            // Ask once per launch; prompting after every dictation is just nagging.
            if !askedForAccessibility {
                askedForAccessibility = true
                Permissions.requestAccessibility(prompt: true)
            }
        case .failed(let message):
            hud.show(.error(message))
        }
    }

    /// Undo the paste in the target app, then paste the text without cloud cleanup.
    private func undoPaste(_ raw: String) {
        Inserter.undo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self else { return }
            _ = Inserter.insert(raw, method: self.settings.insertMethod, restoreClipboard: self.settings.restoreClipboard)
            self.lastTranscript = raw
        }
    }

    private func record(_ dictation: Dictation, audio: URL) {
        var dictation = dictation
        if settings.keepAudio, settings.historyRetention != .off {
            dictation.audio = history.keepAudio(from: audio, for: dictation.id)
        }
        history.add(dictation, retention: settings.historyRetention)
    }

    // MARK: - Menu bar

    /// An accessory app shows no menu bar, but ⌘C/⌘V/⌘A in text fields still
    /// go through the main menu. Without an Edit menu, pasting a license key fails.
    private func installEditMenu() {
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editItem.submenu = edit
        let main = NSMenu()
        main.addItem(NSMenuItem())  // the app menu slot comes first
        main.addItem(editItem)
        NSApp.mainMenu = main
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.toolTip = "Foxtation"
        statusItem = item
        refreshStatusItem()
    }

    /// Fox silhouette as a template image, so macOS tints it like other menu bar icons.
    private static let menuBarIcon: NSImage? = {
        guard let url = Bundle.main.url(forResource: "MenuBarIcon", withExtension: "png"),
              let image = NSImage(contentsOf: url) else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()

    private func refreshStatusItem() {
        guard let item = statusItem else { return }
        // Red while recording, dimmed while transcribing.
        item.button?.image = Self.menuBarIcon
        item.button?.contentTintColor = phase == .recording ? .systemRed : nil
        item.button?.appearsDisabled = phase == .transcribing

        let menu = NSMenu()
        let hotKeyLabel = HotKey.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)

        switch phase {
        case .idle:
            let trigger = settings.holdRightOption ? "hold right ⌥" : hotKeyLabel
            let start = NSMenuItem(title: "Start Dictation  (\(trigger))",
                                   action: #selector(menuStart), keyEquivalent: "")
            start.target = self
            menu.addItem(start)
            if settings.holdRightOption {
                let hint = NSMenuItem(title: "Double-tap right ⌥ for hands-free · \(hotKeyLabel) also works",
                                      action: nil, keyEquivalent: "")
                hint.isEnabled = false
                menu.addItem(hint)
            }
        case .recording:
            let stop = NSMenuItem(title: "Stop & Transcribe", action: #selector(menuStop), keyEquivalent: "")
            stop.target = self
            menu.addItem(stop)
            let cancel = NSMenuItem(title: "Cancel", action: #selector(menuCancel), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        case .transcribing:
            let cancel = NSMenuItem(title: "Cancel", action: #selector(menuCancel), keyEquivalent: "")
            cancel.target = self
            menu.addItem(cancel)
        }

        menu.addItem(.separator())

        if let last = lastTranscript {
            let preview = last.count > 52 ? String(last.prefix(52)) + "…" : last
            let copy = NSMenuItem(title: "Copy Last: “\(preview)”", action: #selector(menuCopyLast), keyEquivalent: "")
            copy.target = self
            menu.addItem(copy)
            menu.addItem(.separator())
        }

        let current = settings.language == "auto" ? "Auto" : Settings.label(for: settings.language)
        let languageItem = NSMenuItem(title: "Language: \(current)", action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        for code in ["auto"] + settings.spokenLanguages {
            let item = NSMenuItem(title: code == "auto" ? "Auto" : Settings.label(for: code), action: #selector(menuLanguage), keyEquivalent: "")
            item.target = self
            item.representedObject = code
            item.state = code == settings.language ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        let openItem = NSMenuItem(title: "Open Foxtation…", action: #selector(menuOpen), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(menuSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        if !Permissions.accessibilityGranted {
            let grant = NSMenuItem(title: "Grant Accessibility Access…", action: #selector(menuGrantAccessibility), keyEquivalent: "")
            grant.target = self
            menu.addItem(grant)
        }

        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit Foxtation", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        item.menu = menu
    }

    @objc private func menuStart() { startRecording() }
    @objc private func menuStop() { finishRecording() }
    @objc private func menuCancel() { cancelTranscription() }
    @objc private func menuSettings() { showSettings() }
    @objc private func menuOpen() { mainWindow.show() }

    @objc private func menuLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        settings.language = code
        refreshStatusItem()
    }
    @objc private func menuGrantAccessibility() { Permissions.requestAccessibility(prompt: true) }

    @objc private func menuCopyLast() {
        guard let last = lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(last, forType: .string)
        hud.show(.message("Copied to clipboard", seconds: 1.4))
    }

    @objc private func menuQuit() { NSApp.terminate(nil) }

    // MARK: - Settings window

    func showSettings(_ section: SettingsSection = .general) {
        mainWindow.show(settings: section)
    }

    /// Settings with side effects; runs after every settings write.
    private func applySettings() {
        registerHotKey()
        applyRightOption()
        wireRecorder()
        refreshStatusItem()
        applyLaunchAtLogin()
    }

    private func makeAppModel() -> AppModel {
        let model = AppModel(settings: settings, history: history, library: library, cloud: cloud)
        // Dictating from the window: hand focus back to the previous app first,
        // so the text lands there and not in Foxtation.
        model.startDictation = { [weak self] in
            guard let self else { return }
            if self.phase != .idle { self.finishRecording(); return }
            NSApp.hide(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.startRecording() }
        }
        model.settingsChanged = { [weak self] in self?.applySettings() }
        return model
    }

    func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        // Settings changes fire for every field; only act when this one changed.
        guard appliedLaunchAtLogin != settings.launchAtLogin else { return }
        appliedLaunchAtLogin = settings.launchAtLogin
        let service = SMAppService.mainApp
        do {
            if settings.launchAtLogin {
                if service.status != .enabled { try service.register() }
            } else {
                if service.status == .enabled { try service.unregister() }
            }
        } catch {
            NSLog("Foxtation: launch-at-login failed: %@", error.localizedDescription)
            // Show the real state instead of a toggle that lies.
            let enabled = service.status == .enabled
            appliedLaunchAtLogin = enabled
            settings.launchAtLogin = enabled
            hud.show(.error("Launch at login failed"))
        }
    }

    // MARK: - First-run guidance

    private func showStartupGuidanceIfNeeded() {
        // The Accessibility prompt is a system dialog, so ask for it regardless
        // of whether an engine message is also shown.
        if !Permissions.accessibilityGranted {
            askedForAccessibility = true
            Permissions.requestAccessibility(prompt: true)
        }
        if settings.engine == .cloud, settings.activationID.isEmpty {
            showSettings(.license)
            hud.show(.error("Foxtation Cloud needs Foxtation Pro — activate your license"))
        } else if settings.engine == .whisperKit, !WhisperKitEngine.shared.isInstalled {
            // First run: open the Engine screen so the download is one click away.
            showSettings(.engine)
            hud.show(.error("Speech model not installed — press Download in Settings › Engine, or activate Foxtation Pro to skip it"))
        } else if settings.engine == .mlx, MLXRuntime.shared.readyPython() == nil {
            hud.show(.error("MLX runtime not installed — open Settings › Engine and press Set Up"))
        } else if settings.engine == .whisperCpp,
                  Transcriber.resolveBinary(configured: settings.whisperBinary) == nil {
            hud.show(.error("whisper.cpp not found — run: brew install whisper-cpp"))
        } else if settings.engine == .whisperCpp,
                  settings.modelPath.isEmpty || !FileManager.default.fileExists(atPath: settings.modelPath) {
            hud.show(.error("No speech model selected — open Settings › Engine to download one"))
        } else if !Permissions.accessibilityGranted {
            hud.show(.error("Grant Accessibility access so text can be typed into other apps"))
        }
    }

    // MARK: - Model discovery

    static func discoverModels() -> [URL] {
        var roots: [URL] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        roots.append(home.appendingPathComponent("Library/Application Support/Foxtation/models", isDirectory: true))
        roots.append(home.appendingPathComponent(".cache/whisper.cpp", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/opt/homebrew/share/whisper.cpp", isDirectory: true))
        roots.append(URL(fileURLWithPath: "/usr/local/share/whisper.cpp", isDirectory: true))
        roots.append(Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/models", isDirectory: true))

        var found: [URL] = []
        for root in roots {
            guard let entries = try? FileManager.default.contentsOfDirectory(at: root,
                                                                             includingPropertiesForKeys: nil) else { continue }
            for entry in entries where entry.pathExtension == "bin" {
                found.append(entry)
            }
        }
        return found
    }
}
