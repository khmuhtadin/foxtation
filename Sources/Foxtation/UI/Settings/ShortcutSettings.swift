import AppKit
import SwiftUI

struct ShortcutSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowsCard {
                SettingRow(title: "Shortcut", detail: "Click, then press the new keys. Must include ⌃ or ⌥, so it can’t clash with ⌘V, ⌘C and other app shortcuts.") {
                    ShortcutRecorder(settings: model.settings).frame(width: 140, height: 28)
                }
                RowDivider()
                SettingRow(title: "Shortcut mode", detail: nil) {
                    MenuPicker(selection: model.setting(\.triggerMode),
                               items: [(.toggle, "Press to start, again to stop"), (.hold, "Hold while speaking")])
                }
                RowDivider()
                SettingRow(title: "Hold right ⌥ to talk", detail: "Double-tap it for hands-free.") {
                    FXSwitch(label: "Hold right ⌥ to talk", isOn: model.setting(\.holdRightOption))
                }
            }
            SettingsNote(text: "Esc cancels recording a new shortcut and keeps the current one.")
        }
    }
}

/// The AppKit hot key recorder from the old settings window.
struct ShortcutRecorder: NSViewRepresentable {
    let settings: Settings

    func makeNSView(context: Context) -> RecorderButton {
        let button = RecorderButton()
        button.onCapture = { code, modifiers in
            settings.hotKeyCode = code
            settings.hotKeyModifiers = modifiers
        }
        return button
    }

    func updateNSView(_ button: RecorderButton, context: Context) {
        button.update(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }
}
