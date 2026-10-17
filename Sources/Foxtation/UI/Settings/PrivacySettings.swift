import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct PrivacySettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "lock").foregroundStyle(Color.fxGood)
                Text("Your voice never leaves this Mac. Only the text transcript is sent to Foxtation Cloud for cleanup, and it isn’t stored after the reply.")
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxGood.opacity(0.10)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.fxGood.opacity(0.30)))

            RowsCard {
                SettingRow(title: "Cloud cleanup", detail: "Off: paste the raw on-device transcript, nothing sent.") {
                    FXSwitch(label: "Cloud cleanup", isOn: model.setting(\.cloudCleanup))
                }
                RowDivider()
                SettingRow(title: "Share the app name", detail: "Sends “Slack” or “Mail” so cleanup can match the style.") {
                    FXSwitch(label: "Share the app name", isOn: model.setting(\.shareAppName))
                }
                RowDivider()
                SettingRow(title: "Keep history on this Mac", detail: "Transcripts shown on Home. Stored locally only.") {
                    MenuPicker(selection: retention, items: HistoryRetention.allCases.map { ($0, $0.label) })
                }
                RowDivider()
                SettingRow(title: "Keep audio recordings", detail: "Lets you replay a dictation. Uses disk space.") {
                    FXSwitch(label: "Keep audio recordings", isOn: model.setting(\.keepAudio))
                }
            }

            HStack(spacing: 8) {
                Text("\(Format.number(model.history.entries.count)) dictations · \(Format.bytes(model.history.diskBytes)) on disk")
                    .font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                Spacer()
                Button("Export history") { export() }.fxButton(.secondary, compact: true)
                Button("Delete all history") { deleteAll() }.fxButton(.destructive, compact: true)
                    .disabled(model.history.entries.isEmpty)
            }
        }
    }

    /// Writes the setting and drops what the new window no longer keeps.
    private var retention: Binding<HistoryRetention> {
        Binding(get: { model.settings.historyRetention }, set: { value in
            model.settings.historyRetention = value
            model.history.prune(value)
        })
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Foxtation History.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.history.export(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    private func deleteAll() {
        guard confirm("Delete all history?",
                      "Every dictation and saved recording on this Mac is removed. This can’t be undone.",
                      action: "Delete All") else { return }
        model.history.deleteAll()
    }
}
