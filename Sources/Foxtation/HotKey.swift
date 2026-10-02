import AppKit
import Carbon
import Carbon.HIToolbox

/// A system-wide hot key built on Carbon's RegisterEventHotKey. Unlike
/// NSEvent global monitors this needs no Input Monitoring permission, and
/// unlike an event tap it cannot be disabled by secure input.
final class HotKey {

    /// Default: ⌃⌥⌘D — unlikely to collide with anything.
    static let defaultKeyCode = UInt32(kVK_ANSI_D)
    static let defaultModifiers = UInt32(controlKey | optionKey | cmdKey)

    private static var registry: [UInt32: HotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let ref: EventHotKeyRef
    private let id: UInt32
    private let onPress: () -> Void
    private let onRelease: () -> Void

    private init?(keyCode: UInt32, modifiers: UInt32, onPress: @escaping () -> Void, onRelease: @escaping () -> Void) {
        self.onPress = onPress
        self.onRelease = onRelease
        self.id = HotKey.nextID
        HotKey.nextID += 1

        var hotKeyID = EventHotKeyID(signature: OSType(0x574B4559), id: id)  // legacy signature, any 4CC works
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                         GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else { return nil }
        self.ref = ref

        HotKey.installHandlerIfNeeded()
        HotKey.registry[id] = self
    }

    deinit {
        UnregisterEventHotKey(ref)
        HotKey.registry[id] = nil
    }

    static func register(keyCode: UInt32, modifiers: UInt32,
                         onPress: @escaping () -> Void,
                         onRelease: @escaping () -> Void) -> HotKey? {
        HotKey(keyCode: keyCode, modifiers: modifiers, onPress: onPress, onRelease: onRelease)
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        handlerInstalled = true

        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(event, EventParamName(kEventParamDirectObject),
                                        EventParamType(typeEventHotKeyID), nil,
                                        MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            guard err == noErr, let hotKey = HotKey.registry[hotKeyID.id] else { return noErr }

            let isPress = GetEventKind(event) == UInt32(kEventHotKeyPressed)
            DispatchQueue.main.async {
                if isPress { hotKey.onPress() } else { hotKey.onRelease() }
            }
            return noErr
        }, 2, &specs, nil, nil)
    }

    // MARK: - Display

    static func describe(keyCode: UInt32, modifiers: UInt32) -> String {
        var parts: [String] = []
        if modifiers & UInt32(controlKey) != 0 { parts.append("⌃") }
        if modifiers & UInt32(optionKey) != 0 { parts.append("⌥") }
        if modifiers & UInt32(shiftKey) != 0 { parts.append("⇧") }
        if modifiers & UInt32(cmdKey) != 0 { parts.append("⌘") }
        parts.append(keyName(keyCode))
        return parts.joined()
    }

    private static let keyNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Escape: "⎋",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←",
        kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
        kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10",
        kVK_F11: "F11", kVK_F12: "F12",
    ]

    private static func keyName(_ code: UInt32) -> String {
        if let named = keyNames[Int(code)] { return named }
        if let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
           let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) {
            let layout = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
            var deadKeyState: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = layout.withUnsafeBytes { raw -> OSStatus in
                guard let base = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
                return UCKeyTranslate(base, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                      UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                      &deadKeyState, chars.count, &length, &chars)
            }
            if status == noErr, length > 0 {
                return String(utf16CodeUnits: chars, count: length).uppercased()
            }
        }
        return "Key \(code)"
    }
}
