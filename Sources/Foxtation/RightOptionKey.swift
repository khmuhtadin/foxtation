import AppKit

/// Watches the right Option key on its own. Carbon hot keys can't register a
/// bare modifier, so this uses NSEvent monitors; the global one needs
/// Accessibility, which the app already asks for to paste.
final class RightOptionKey {

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Another key was pressed while right ⌥ was held (e.g. ⌥E for é), so the
    /// user is typing, not dictating.
    var onChord: (() -> Void)?

    private static let keyCode: UInt16 = 61
    private static let deviceMask: UInt = 0x40  // NX_DEVICERALTKEYMASK: right ⌥ specifically

    private var monitors: [Any] = []
    private var isDown = false

    func start() {
        guard monitors.isEmpty else { return }
        let flags: (NSEvent) -> Void = { [weak self] event in self?.flagsChanged(event) }
        let keys: (NSEvent) -> Void = { [weak self] _ in self?.otherKey() }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: flags) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: keys) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { flags($0); return $0 }) { monitors.append(m) }
        if let m = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { keys($0); return $0 }) { monitors.append(m) }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
        isDown = false
    }

    private func flagsChanged(_ event: NSEvent) {
        guard event.keyCode == Self.keyCode else {
            otherKey()  // another modifier joined in, e.g. ⌥⇧
            return
        }
        let down = event.modifierFlags.rawValue & Self.deviceMask != 0
        guard down != isDown else { return }
        isDown = down
        if down { onPress?() } else { onRelease?() }
    }

    private func otherKey() {
        if isDown { onChord?() }
    }
}
