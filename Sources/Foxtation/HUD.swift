import AppKit
import SwiftUI

/// The dictation pill. AppDelegate drives it with `show`, `updateLevel`,
/// `hide` and `cancel`; everything visual lives under HUD/.
final class HUD {

    enum State {
        case listening
        case working
        /// Waiting for Foxtation Cloud; `app` is the target app's name.
        case cleaning(app: String)
        /// Pasted. `undo` swaps in the raw transcript; nil hides the button.
        case pasted(words: Int, undo: (() -> Void)?)
        /// Pasted the raw transcript because cleanup failed; the reason is short.
        case fallback(String)
        case message(String, seconds: TimeInterval)
        case error(String)
    }

    /// Called when the user presses esc while the pill is up.
    var onCancel: (() -> Void)?

    private let model = HUDModel()
    private lazy var window = DictationHUDWindow(model: model)
    private let dismissTimer = DismissTimer()
    private var keyMonitors: [Any] = []
    private var followTimer: Timer?
    private var undoAction: (() -> Void)?
    /// True from show until the fade-out finishes ordering the window out.
    private var isVisible = false
    /// Bumped on every show, so a late fade-out can't hide a newer pill.
    private var generation = 0

    init() {
        model.onClose = { [weak self] in self?.escPressed() }
        model.onAction = { [weak self] in
            self?.undoAction?()
            self?.hide()
        }
        model.onHover = { [weak self] hovering in
            if hovering { self?.dismissTimer.pause() } else { self?.dismissTimer.resume() }
        }
        window.prewarm()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.isVisible else { return }
            self.window.place()
        }
    }

    // MARK: - Presentation

    func show(_ state: State) {
        let hudState: HUDState
        let label: String
        var detail = ""
        var autoDismiss: TimeInterval?
        undoAction = nil
        switch state {
        case .listening:
            hudState = .listening
            label = "Listening"
        case .working:
            hudState = .processing
            label = "Transcribing…"
        case .cleaning(let app):
            hudState = .processing
            label = app.isEmpty ? "Cleaning up…" : "Cleaning up for"
            detail = app
        case .pasted(let words, let undo):
            hudState = .success
            label = "Pasted"
            detail = "· \(words) word\(words == 1 ? "" : "s")"
            undoAction = undo
            autoDismiss = undo == nil ? 1.4 : 2.5
        case .fallback(let reason):
            NSLog("Foxtation: pasted raw transcript (%@)", reason)
            hudState = .warning
            label = reason
            detail = "· raw text pasted"
            autoDismiss = 3
        case .message(let text, let seconds):
            hudState = .success
            label = Self.pillText(text)
            autoDismiss = max(0.6, seconds)
        case .error(let text):
            NSLog("Foxtation: %@", text)
            hudState = .error
            label = Self.pillText(text)
            autoDismiss = 4
        }

        dismissTimer.cancel()

        if isVisible {
            // Only colors and text change between states.
            withAnimation(.easeInOut(duration: 0.15)) {
                model.state = hudState
                model.label = label
                model.detail = detail
                model.actionTitle = undoAction == nil ? nil : "Undo"
                if hudState != .listening { model.listeningSince = nil }
            }
        } else {
            model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            model.state = hudState
            model.label = label
            model.detail = detail
            model.actionTitle = undoAction == nil ? nil : "Undo"
            model.listeningSince = hudState == .listening ? Date() : nil
            model.waveformStarted = false
            isVisible = true
            generation += 1
            window.place()
            window.orderFrontRegardless()
            withAnimation(.easeOut(duration: model.reduceMotion ? 0.1 : 0.18)) { model.isShown = true }
            startKeyMonitors()
            startFollowingScreen()
            announce(label)
        }

        if hudState == .success || hudState == .warning { announce(label + " " + detail) }
        if let autoDismiss {
            dismissTimer.start(autoDismiss) { [weak self] in self?.hide() }
        }
    }

    /// Mic level, 0...1, on the main thread.
    func updateLevel(_ level: Float) {
        guard isVisible else { return }
        model.meter.target = Double(level)
        if !model.waveformStarted && level > 0 { model.waveformStarted = true }
    }

    func hide() {
        dismiss()
    }

    /// Same fade as hide; kept separate so callers say what happened.
    func cancel() {
        dismiss()
    }

    private func dismiss() {
        dismissTimer.cancel()
        guard isVisible else { return }
        isVisible = false
        stopKeyMonitors()
        stopFollowingScreen()
        let shown = generation
        withAnimation(.easeIn(duration: 0.15)) { model.isShown = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, self.generation == shown, !self.isVisible else { return }
            self.window.orderOut(nil)
            self.model.state = .hidden
        }
    }

    // MARK: - esc

    /// esc arrives through event monitors, never by the panel becoming key.
    /// The global monitor needs Accessibility, which the app already asks for.
    private func startKeyMonitors() {
        guard keyMonitors.isEmpty else { return }
        let handle: (NSEvent) -> Void = { [weak self] event in
            guard event.keyCode == 53 else { return }
            DispatchQueue.main.async { self?.escPressed() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: handle) {
            keyMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { event in
            handle(event)
            return event
        }) {
            keyMonitors.append(local)
        }
    }

    private func stopKeyMonitors() {
        keyMonitors.forEach(NSEvent.removeMonitor)
        keyMonitors.removeAll()
    }

    private func escPressed() {
        guard isVisible else { return }
        if let onCancel { onCancel() } else { cancel() }
    }

    // MARK: - Screen tracking

    /// Follows the focused window to another screen mid-dictation.
    private func startFollowingScreen() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.window.place()
        }
    }

    private func stopFollowingScreen() {
        followTimer?.invalidate()
        followTimer = nil
    }

    // MARK: - Helpers

    private func announce(_ text: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested, userInfo: [
            .announcement: text,
            .priority: NSAccessibilityPriorityLevel.high.rawValue,
        ])
    }

    /// The pill holds one short line. Long messages are logged in full by
    /// `show` and reduced here to at most four words.
    static func pillText(_ message: String) -> String {
        let known: [(String, String)] = [
            ("Microphone", "Microphone access denied"),
            ("MLX runtime", "MLX not set up"),
            ("mlx_worker", "Worker script missing"),
            ("whisper.cpp not found", "whisper.cpp not installed"),
            ("No speech model", "No model selected"),
            ("grant Accessibility", "Copied — grant Accessibility"),
            ("Grant Accessibility", "Accessibility access needed"),
        ]
        if let match = known.first(where: { message.contains($0.0) }) { return match.1 }

        let firstClause = message
            .components(separatedBy: " — ").first!
            .components(separatedBy: "\n").first!
            .components(separatedBy: ". ").first!
        let words = firstClause.split(separator: " ").prefix(4).joined(separator: " ")
        return words.trimmingCharacters(in: CharacterSet(charactersIn: " .:;,"))
    }
}

/// Auto-dismiss that hover can pause; unhover resumes the remainder.
final class DismissTimer {
    private var work: DispatchWorkItem?
    private var action: (() -> Void)?
    private var remaining: TimeInterval = 0
    private var startedAt: Date?
    private var hovering = false

    func start(_ seconds: TimeInterval, action: @escaping () -> Void) {
        cancel()
        self.action = action
        remaining = seconds
        if !hovering { schedule() }
    }

    func pause() {
        hovering = true
        guard let work, let startedAt else { return }
        work.cancel()
        self.work = nil
        remaining = max(0, remaining - Date().timeIntervalSince(startedAt))
        self.startedAt = nil
    }

    func resume() {
        hovering = false
        if action != nil && work == nil { schedule() }
    }

    func cancel() {
        work?.cancel()
        work = nil
        action = nil
        startedAt = nil
    }

    private func schedule() {
        let item = DispatchWorkItem { [weak self] in
            guard let self, let action = self.action else { return }
            self.cancel()
            action()
        }
        work = item
        startedAt = Date()
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining, execute: item)
    }
}
