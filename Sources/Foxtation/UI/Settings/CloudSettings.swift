import SwiftUI

struct CloudSettings: View {
    @ObservedObject var model: AppModel
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            RowsCard {
                SettingRow(title: "Cloud cleanup",
                           detail: "Foxtation Cloud removes filler words, applies your self-corrections and fixes punctuation before pasting. Off: the raw on-device transcript is pasted.") {
                    FXSwitch(label: "Cloud cleanup", isOn: model.setting(\.cloudCleanup))
                }
                RowDivider()
                SettingRow(title: "Skip when there’s nothing to fix",
                           detail: "Pastes right away when there are no filler words, self-corrections, lists or spoken emoji. Rapi style always uses the cloud.") {
                    FXSwitch(label: "Skip when there’s nothing to fix", isOn: model.setting(\.skipCleanWhenNothingToFix))
                }
                RowDivider()
                if model.cloud.isActivated {
                    SettingRow(title: "Foxtation Cloud", detail: "Activated on this Mac.") {
                        StatusBadge(text: "Active", good: true)
                    }
                } else {
                    SettingRow(title: "Foxtation Cloud", detail: "Not activated on this Mac. Add your key in License.") {
                        Button("Open License") { section = .license }.fxButton(.secondary, compact: true)
                    }
                }
                RowDivider()
                SettingRow(title: "Share the app name", detail: "Sends “Slack” or “Mail” so cleanup can match the style.") {
                    FXSwitch(label: "Share the app name", isOn: model.setting(\.shareAppName))
                }
            }
            SettingsNote(text: "Only the text transcript is sent for cleanup, never audio, and it isn’t stored after the reply.")
        }
    }
}
