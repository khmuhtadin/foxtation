import AppKit
import SwiftUI

/// `Foxtation --ui-test [--dump]` opens the real window off screen with
/// throwaway, in-memory data and clicks and types through it with in-process
/// events (no Accessibility permission needed). Points come from the same
/// 1280×820 layout as `--render-window`. Prints PASS/FAIL per step and exits
/// non-zero on any failure. Nothing is written to disk or sent to the server.
/// `--dump` lists each screen's controls and their frames instead.
/// Borderless like the snapshots, but able to take keyboard focus.
final class TestWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

enum UITest {

    @MainActor
    static func run(dump: Bool) -> Int32 {
        let settings = Settings.shared
        settings.persistsChanges = false
        settings.activationID = ""          // never reach the server from here
        settings.cloudCleanup = false
        let model = AppModel(settings: settings, history: .sample(), library: .sample(),
                             cloud: CloudStatus(settings: settings), isSnapshot: true)
        let window = TestWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.setFrameOrigin(NSPoint(x: -3000, y: -3000))  // off screen
        window.makeKeyAndOrderFront(nil)
        settle()

        if dump {
            for (name, set) in [("home", { model.page = .home }), ("dictionary", { model.page = .dictionary }),
                                ("snippets", { model.page = .snippets }), ("style", { model.page = .style }),
                                ("privacy", { model.settingsSection = .privacy }), ("license", { model.settingsSection = .license })] as [(String, () -> Void)] {
                set()
                settle()
                print("== \(name)")
                for control in controls(in: window.contentView!) { print("  ", control.kind, control.frame.integral) }
            }
            return 0
        }

        var failures = 0
        func step(_ name: String, _ ok: Bool) {
            print(ok ? "PASS" : "FAIL", name)
            if !ok { failures += 1 }
        }
        // Points are in the 1280×820 layout, top-left origin, as in --render-window shots.
        func click(_ x: CGFloat, _ y: CGFloat) { UITest.click(window, x, y) }
        func click(_ target: NSWindow, _ x: CGFloat, _ y: CGFloat) { UITest.click(target, x, y) }
        let library = model.library

        // Sidebar
        click(64, 158); step("sidebar → Dictionary", model.page == .dictionary)
        click(64, 188); step("sidebar → Snippets", model.page == .snippets)
        click(64, 218); step("sidebar → Style", model.page == .style)
        click(64, 128); step("sidebar → Insights", model.page == .insights)
        click(64, 98); step("sidebar → Home", model.page == .home)
        click(1212, 282); step("Home › View all → History", model.page == .history)

        // Dictionary
        click(64, 158)
        let suggestion = library.suggestions(from: model.history.entries).first
        click(595, 198)
        step("suggestion chip adds “\(suggestion ?? "-")”", suggestion.map { s in library.terms.contains { $0.text == s } } ?? false)
        let wordsBefore = library.terms.count
        click(1038, 54)
        step("Add word opens a sheet", window.attachedSheet != nil)
        if let sheet = window.attachedSheet {
            typeText("Durable Object", into: sheet)
            pressReturn(in: sheet)
            step("typing a word and ↩ saves it", library.terms.contains { $0.text == "Durable Object" } && library.terms.count == wordsBefore + 1)
            if window.attachedSheet != nil, let save = controls(in: sheet.contentView!).last(where: { $0.kind == "button" }) {
                click(sheet, save.frame.midX, save.frame.midY)
                step("…or clicking Save saves it", library.terms.contains { $0.text == "Durable Object" })
            }
            if window.attachedSheet != nil { key(window.attachedSheet!, 53) }
        }
        click(1038, 54)
        if let sheet = window.attachedSheet {
            typeText("jakmall", into: sheet)
            pressReturn(in: sheet)
            step("duplicate word is refused", library.terms.filter { $0.text.lowercased() == "jakmall" }.count == 1)
            key(sheet, 53)  // esc
            settle()
        }
        step("esc closes the sheet", window.attachedSheet == nil)

        // Snippets
        click(64, 188)
        let snippetsBefore = library.snippets.count
        click(1004, 54)
        step("New snippet opens a sheet", window.attachedSheet != nil)
        if let sheet = window.attachedSheet {
            typeText("my phone", into: sheet)
            typeInTextView("+62 812 0000 0000", in: sheet)
            key(sheet, 36, command: true)  // ⌘↩
            step("cue and text save with ⌘↩", library.snippets.count == snippetsBefore + 1
                 && library.snippets.contains { $0.cue == "my phone" && $0.text == "+62 812 0000 0000" })
            if window.attachedSheet != nil, let cancel = controls(in: sheet.contentView!).last(where: { $0.kind == "button" }) {
                // Save is the rightmost button, just right of Cancel's key-view proxy.
                click(sheet, sheet.frame.width - 52, cancel.frame.midY)
                step("…or clicking Save saves it", library.snippets.contains { $0.cue == "my phone" && $0.text == "+62 812 0000 0000" })
            }
            if window.attachedSheet != nil { key(window.attachedSheet!, 53) }
        }

        // Style
        click(64, 218)
        click(973, 209)
        step("Polished card sets Chat to formal", library.groups[.chat]?.style == .formal)
        click(455, 367)
        step("× removes WhatsApp from Chat", library.groups[.chat]?.apps.contains { $0.name == "WhatsApp" } == false)
        let emoji = library.spokenEmoji
        click(1084, 444)
        step("emoji switch flips spokenEmoji", library.spokenEmoji != emoji)

        // Settings
        click(64, 762)
        step("sidebar Settings opens the panel", model.settingsSection == .general)
        click(284, 406)
        step("panel → Data & Privacy", model.settingsSection == .privacy)
        let share = model.settings.shareAppName
        click(988, 360)
        step("Share the app name switch", model.settings.shareAppName != share)
        click(264, 375)
        step("panel → License", model.settingsSection == .license)
        key(window, 53)
        step("esc closes Settings", model.settingsSection == nil)

        _ = window
        return failures == 0 ? 0 : 1
    }

    // MARK: - Input

    @MainActor
    static func click(_ window: NSWindow, _ x: CGFloat, _ y: CGFloat) {
        let point = NSPoint(x: x, y: window.frame.height - y)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            NSApp.sendEvent(event)
        }
        settle()
    }

    @MainActor
    static func key(_ window: NSWindow, _ code: UInt16, command: Bool = false) {
        window.makeKey()
        let characters = code == 36 ? "\r" : code == 53 ? "\u{1b}" : ""
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: command ? [.command] : [],
                                         timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                                         context: nil, characters: characters, charactersIgnoringModifiers: characters,
                                         isARepeat: false, keyCode: code)!
            NSApp.sendEvent(event)
        }
        settle()
    }

    /// What a real Return does in a focused text field: the field editor's insertNewline.
    @MainActor
    static func pressReturn(in window: NSWindow) {
        window.makeKey()
        (window.firstResponder as? NSTextView)?.insertNewline(nil)
        settle()
    }

    /// Types into the first editable text field in `window`.
    @MainActor
    static func typeText(_ text: String, into window: NSWindow) {
        guard let field = controls(in: window.contentView!).first(where: { $0.kind == "field" })?.view as? NSTextField else { return }
        window.makeFirstResponder(field)
        (field.currentEditor() as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
    }

    /// Types into the first editable multi-line text view in `window`.
    @MainActor
    static func typeInTextView(_ text: String, in window: NSWindow) {
        // Skip field editors: they sit on top of a text field with the same frame.
        let fields = controls(in: window.contentView!).filter { $0.kind == "field" }.map(\.frame)
        guard let view = controls(in: window.contentView!)
            .first(where: { $0.kind == "textview" && !fields.contains($0.frame) })?.view as? NSTextView else { return }
        window.makeFirstResponder(view)
        view.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        settle()
    }

    // MARK: - Controls

    struct Control {
        var kind: String
        var frame: CGRect      // in the window's content view, top-left origin
        var view: NSView
    }

    /// Clickable SwiftUI buttons (their key-view proxies, switches included) and text fields, top to bottom.
    static func controls(in host: NSView) -> [Control] {
        var found: [Control] = []
        func walk(_ view: NSView) {
            let name = "\(type(of: view))"
            let frame = view.convert(view.bounds, to: host)
            if name.contains("KeyViewProxy") { found.append(Control(kind: "button", frame: frame, view: view)) }
            else if let field = view as? NSTextField, field.isEditable { found.append(Control(kind: "field", frame: frame, view: view)) }
            else if view is NSTextView, (view as! NSTextView).isEditable { found.append(Control(kind: "textview", frame: frame, view: view)) }
            view.subviews.forEach(walk)
        }
        walk(host)
        return found.sorted { ($0.frame.minY, $0.frame.minX) < ($1.frame.minY, $1.frame.minX) }
    }

    /// Lets SwiftUI lay out, draw and run its updates.
    @MainActor
    static func settle(_ seconds: Double = 0.4) {
        RunLoop.current.run(until: Date().addingTimeInterval(seconds))
    }
}
