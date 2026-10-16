import AppKit
import Carbon.HIToolbox

/// Click, then press a key combination; reports Carbon key code and modifiers.
final class RecorderButton: NSView {

    var onCapture: ((UInt32, UInt32) -> Void)?

    private var code: UInt32 = 0
    private var mods: UInt32 = 0
    private var recording = false
    private let label = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 6
        layer?.borderWidth = 1

        label.alignment = .center
        label.font = .systemFont(ofSize: 12, weight: .medium)
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
        refreshChrome()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var acceptsFirstResponder: Bool { true }
    override var wantsUpdateLayer: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        recording = true
        refreshChrome()
    }

    override func resignFirstResponder() -> Bool {
        recording = false
        refreshChrome()
        return true
    }

    override func keyDown(with event: NSEvent) {
        let flags = event.modifierFlags
        var carbon: UInt32 = 0
        if flags.contains(.control) { carbon |= UInt32(controlKey) }
        if flags.contains(.option) { carbon |= UInt32(optionKey) }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey) }
        if flags.contains(.command) { carbon |= UInt32(cmdKey) }

        // Ignore presses of the modifier keys themselves.
        let modifierKeyCodes: Set<Int> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
        if modifierKeyCodes.contains(Int(event.keyCode)) { return }
        // Escape cancels recording and keeps the current shortcut.
        if event.keyCode == 53, carbon == 0 {
            window?.makeFirstResponder(nil)
            return
        }
        // Shift alone would hijack ordinary typing (⇧A = capital A) system-wide.
        guard carbon & UInt32(cmdKey | optionKey | controlKey) != 0 else { NSSound.beep(); return }

        code = UInt32(event.keyCode)
        mods = carbon
        recording = false
        window?.makeFirstResponder(nil)
        onCapture?(code, mods)
        refreshChrome()
    }

    func update(keyCode: UInt32, modifiers: UInt32) {
        if recording, window?.firstResponder !== self {
            recording = false  // window was closed or focus moved away mid-recording
        }
        guard !recording else { return }
        code = keyCode
        mods = modifiers
        refreshChrome()
    }

    private func refreshChrome() {
        label.stringValue = recording ? "Press shortcut…" : HotKey.describe(keyCode: code, modifiers: mods)
        label.textColor = recording ? Palette.accent : Palette.ink
        needsDisplay = true
    }

    override func updateLayer() {
        layer?.borderColor = (recording ? Palette.accent : Palette.track).cgColor
        layer?.backgroundColor = (recording ? Palette.accent.withAlphaComponent(0.10) : Palette.background).cgColor
    }
}
