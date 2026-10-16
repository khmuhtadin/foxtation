import SwiftUI

struct SoundSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RowsCard {
                SettingRow(title: "Start and stop sounds", detail: "A soft click when recording starts and ends.") {
                    FXSwitch(isOn: model.setting(\.playSounds))
                }
                RowDivider()
                SettingRow(title: "Floating indicator", detail: "The pill at the bottom of the screen while you dictate.") {
                    FXSwitch(isOn: model.setting(\.showHUD))
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Inserting text")
                RowsCard {
                    SettingRow(title: "Insert by", detail: nil) {
                        MenuPicker(selection: model.setting(\.insertMethod),
                                   items: [(.paste, "Paste (⌘V)"), (.type, "Type characters")])
                    }
                    RowDivider()
                    SettingRow(title: "Restore clipboard afterwards", detail: "Puts back what you had copied before the paste.") {
                        FXSwitch(isOn: model.setting(\.restoreClipboard))
                            .disabled(model.settings.insertMethod == .type)
                    }
                }
            }
        }
    }
}
