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
                    FXSwitch(label: "Hold right ⌥ to talk", isOn: model.setting(\.holdRightOption))
                }
                RowDivider()
                SettingRow(title: "Microphone", detail: model.microphoneName) {
                    Button("Change") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension?input")!)
                    }
                    .fxButton(.secondary, compact: true)
                }
                RowDivider()
                languagesRow
                RowDivider()
                SettingRow(title: "Dictation language", detail: "Auto picks among your languages and keeps mixed speech mixed.") {
                    MenuPicker(selection: model.setting(\.language),
                               items: [("auto", "Auto")] + model.settings.spokenLanguages.map { ($0, Settings.label(for: $0)) })
                }
                RowDivider()
                SettingRow(title: "Translate to English", detail: "Paste English whatever language you speak.") {
                    FXSwitch(label: "Translate to English", isOn: model.setting(\.translate))
                }
                RowDivider()
                SettingRow(title: "Launch at login", detail: "Keep Foxtation ready in the menu bar.") {
                    FXSwitch(label: "Launch at login", isOn: model.setting(\.launchAtLogin))
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

    /// The languages Foxtation listens for. Fewer to choose from means fewer
    /// wrong guesses, so only the ones this person speaks.
    private var languagesRow: some View {
        let spoken = model.settings.spokenLanguages
        let others = Settings.languages.filter { !spoken.contains($0.code) }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Languages you speak").font(FXFont.body.weight(.medium)).foregroundStyle(Color.fxInk)
                Text("Foxtation only listens for these, so it never mistakes yours for another.")
                    .font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            StyleFlowLayout(spacing: 6) {
                ForEach(spoken, id: \.self) { code in
                    Chip(text: Settings.label(for: code), onRemove: spoken.count > 1 ? { removeLanguage(code) } : nil)
                }
                Menu {
                    ForEach(others, id: \.code) { language in
                        Button(language.label) { model.settings.spokenLanguages.append(language.code) }
                    }
                } label: {
                    Text("Add language…").font(FXFont.detail.weight(.medium)).foregroundStyle(Color.fxAccent)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .frame(height: 26)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func removeLanguage(_ code: String) {
        model.settings.spokenLanguages.removeAll { $0 == code }
        if model.settings.language == code { model.settings.language = "auto" }
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
