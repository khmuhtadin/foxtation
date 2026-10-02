import AppKit
import Carbon.HIToolbox

/// Delivers transcribed text into whatever field currently has focus.
enum Inserter {

    enum Outcome {
        case inserted
        case copiedOnly          // no Accessibility permission — text is on the clipboard
        case failed(String)
    }

    static func insert(_ text: String, method: InsertMethod, restoreClipboard: Bool) -> Outcome {
        guard !text.isEmpty else { return .inserted }

        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(of: pasteboard) : nil
        let savedChangeCount = pasteboard.changeCount

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        guard Permissions.accessibilityGranted else { return .copiedOnly }

        switch method {
        case .paste:
            postCommandV()
        case .type:
            typeUnicode(text)
        }

        if let saved, restoreClipboard {
            // Only restore if nothing else touched the clipboard in the meantime.
            // Slow targets (Electron, busy apps) read the pasteboard late, so wait.
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                guard pasteboard.changeCount == savedChangeCount + 1 else { return }
                pasteboard.clearContents()
                pasteboard.writeObjects(saved)
            }
        }
        return .inserted
    }

    // MARK: - Synthetic input

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        source?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval)

        let vKey = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }

    /// Emits the string as Unicode key events. Used when the target app does not
    /// accept a synthetic paste. Chunked because each event carries a limited
    /// number of UTF-16 units.
    private static func typeUnicode(_ text: String) {
        let source = CGEventSource(stateID: .combinedSessionState)
        // Chunk by Character so a surrogate pair (emoji) is never split.
        var chunks: [[UniChar]] = [[]]
        for character in text {
            let units = Array(String(character).utf16)
            if chunks[chunks.count - 1].count + units.count > 16 { chunks.append([]) }
            chunks[chunks.count - 1].append(contentsOf: units)
        }

        for chunk in chunks where !chunk.isEmpty {
            guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else { break }
            down.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            up.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
        }
    }

    // MARK: - Pasteboard

    private static func snapshot(of pasteboard: NSPasteboard) -> [NSPasteboardItem]? {
        guard let items = pasteboard.pasteboardItems else { return nil }
        var copies: [NSPasteboardItem] = []
        for item in items {
            let copy = NSPasteboardItem()
            var carried = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    carried = true
                }
            }
            if carried { copies.append(copy) }
        }
        return copies.isEmpty ? nil : copies
    }
}
