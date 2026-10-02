import AppKit
import SwiftUI

/// The dictation pill. AppDelegate drives it with `show`, `updateLevel`,
/// `hide` and `cancel`; everything visual lives under HUD/.
final class HUD {

    enum State {
        case listening
        case working
        case message(String, seconds: TimeInterval)
        case error(String)
    }

    /// Called when the user presses esc while the pill is up.
    var onCancel: (() -> Void)?

    var placement: HUDPlacement = .rightEdge {
        didSet {
            model.placement = placement
            if model.isVisible { window.place(placement) }
        }
    }

    private let model = HUDModel()
    private let flight = FoxFlight()
    private lazy var window = DictationHUDWindow(model: model, flight: flight)
    private let dismissTimer = DismissTimer()
    private var keyMonitors: [Any] = []
    private var followTimer: Timer?
    private var lastFoxLevel = Date.distantPast

    init() {
        model.onHover = { [weak self] hovering in
            if hovering { self?.dismissTimer.pause() } else { self?.dismissTimer.resume() }
        }
        window.prewarm()
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            guard let self, self.model.isVisible else { return }
            self.window.place(self.placement)
        }
    }

    // MARK: - Presentation

    func show(_ state: State) {
        let hudState: HUDState
        let label: String
        var autoDismiss: TimeInterval?
        switch state {
        case .listening:
            hudState = .listening
            label = "Listening…"
        case .working:
            hudState = .processing
            label = "Transcribing…"
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
        model.fox.setState(hudState.foxState)

        if model.isVisible {
            // Recording ended (or failed) before the fox landed: seat it now.
            if hudState != .listening { model.finishEntry(flight: flight) }
            // Only colors and the fox pose change between states.
            withAnimation(.easeInOut(duration: 0.18)) {
                model.state = hudState
                model.label = label
            }
        } else {
            model.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            model.state = hudState
            model.label = label
            model.waveformStarted = false
            model.isVisible = true
            model.fox.isPaused = false
            window.place(placement)
            window.orderFrontRegardless()
            model.runEntry(flight: flight)
            startKeyMonitors()
            startFollowingScreen()
            announce(label)
        }

        if hudState == .success { announce(label) }
        if let autoDismiss {
            dismissTimer.start(autoDismiss) { [weak self] in self?.hide() }
        }
    }

    /// Mic level, 0...1, on the main thread.
    func updateLevel(_ level: Float) {
        guard model.isVisible else { return }
        model.meter.target = Double(level)
        if !model.waveformStarted && level > 0 { model.waveformStarted = true }
        // The fox only needs ~20Hz.
        let now = Date()
        if now.timeIntervalSince(lastFoxLevel) >= 0.05 {
            lastFoxLevel = now
            model.fox.setAmplitude(Double(level))
        }
    }

    func hide() {
        dismiss(model.state == .success ? .success : .normal)
    }

    /// Collapses straight out; never shows success.
    func cancel() {
        dismiss(.cancelled)
    }

    private func dismiss(_ kind: HUDModel.ExitKind) {
        dismissTimer.cancel()
        guard model.isVisible else { return }
        model.isVisible = false
        stopKeyMonitors()
        stopFollowingScreen()
        if kind == .cancelled { model.state = .cancelled }
        model.runExit(kind, flight: flight) { [weak self] in
            guard let self else { return }
            self.window.orderOut(nil)
            self.model.state = .hidden
            self.model.fox.setState(.idle)
            self.model.fox.isPaused = true
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
        guard model.isVisible else { return }
        if let onCancel { onCancel() } else { cancel() }
    }

    // MARK: - Screen tracking

    /// Follows the focused window to another screen mid-dictation.
    private func startFollowingScreen() {
        followTimer?.invalidate()
        followTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.window.place(self.placement)
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
