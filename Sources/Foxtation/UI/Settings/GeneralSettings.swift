import AppKit
import Combine
import SwiftUI

struct GeneralSettings: View {
    @ObservedObject var model: AppModel
    @Binding var section: SettingsSection

    @StateObject private var grants = PermissionGrants()
    // Grants happen in System Settings; poll so the rows update without a reopen.
    private let poll = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            RowsCard {
                pushToTalkRow
                RowDivider()
                SettingRow(title: "Hold right ⌥ to talk", detail: "Double-tap it for hands-free.") {
                    FXSwitch(isOn: model.setting(\.holdRightOption))
                }
                RowDivider()
                SettingRow(title: "Microphone", detail: model.microphoneName) {
                    Button("Change") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input")!)
                    }
                    .fxButton(.secondary, compact: true)
                }
                RowDivider()
                SettingRow(title: "Dictation language", detail: "Auto detect keeps mixed speech mixed.") {
                    MenuPicker(selection: model.setting(\.language), items: Settings.languages.map { ($0.code, $0.label) })
                }
                RowDivider()
                SettingRow(title: "Translate to English", detail: "Paste English whatever language you speak.") {
                    FXSwitch(isOn: model.setting(\.translate))
                }
                RowDivider()
                SettingRow(title: "Launch at login", detail: "Keep Foxtation ready in the menu bar.") {
                    FXSwitch(isOn: model.setting(\.launchAtLogin))
                }
            }

            if !grants.microphone || !grants.accessibility {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel(text: "Permissions")
                    RowsCard {
                        permissionRow("Microphone", detail: "Records your voice", granted: grants.microphone) {
                            Permissions.requestMicrophone { granted in
                                if !granted { Permissions.openMicrophoneSettings() }
                            }
                        }
                        RowDivider()
                        permissionRow("Accessibility", detail: "Pastes text into other apps", granted: grants.accessibility) {
                            Permissions.requestAccessibility(prompt: true)
                            Permissions.openAccessibilitySettings()
                        }
                    }
                }
            }
        }
        .onReceive(poll) { _ in refreshPermissions() }
        .onAppear { refreshPermissions() }
    }

    /// "Hold [right ⌥] and speak. Release to paste." with the key drawn as a cap.
    private var pushToTalkRow: some View {
        let holds = model.settings.holdRightOption || model.settings.triggerMode == .hold
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Push-to-talk").font(FXFont.body.weight(.medium)).foregroundStyle(Color.fxInk)
                HStack(spacing: 5) {
                    Text(holds ? "Hold" : "Press")
                    KeyCap(text: model.triggerKey)
                    Text(holds ? "and speak. Release to paste." : "to start, press again to paste.")
                }
                .font(FXFont.detail)
                .foregroundStyle(Color.fxSecondary)
            }
            Spacer(minLength: 12)
            Button("Change") { section = .shortcuts }.fxButton(.secondary, compact: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func permissionRow(_ title: String, detail: String, granted: Bool, grant: @escaping () -> Void) -> some View {
        SettingRow(title: title, detail: detail) {
            HStack(spacing: 10) {
                HStack(spacing: 5) {
                    Circle().fill(granted ? Color.fxGood : Color.fxBad).frame(width: 6, height: 6)
                    Text(granted ? "Granted" : "Not granted").font(FXFont.detail.weight(.medium))
                        .foregroundStyle(granted ? Color.fxGood : Color.fxBad)
                }
                if !granted {
                    Button("Grant…", action: grant).fxButton(.primary, compact: true)
                }
            }
        }
    }

    private func refreshPermissions() {
        // Snapshots show the board's state, not this machine's grants.
        grants.microphone = model.isSnapshot || Permissions.microphoneGranted
        grants.accessibility = model.isSnapshot || Permissions.accessibilityGranted
    }
}

final class PermissionGrants: ObservableObject {
    @Published var microphone = true
    @Published var accessibility = true
}
