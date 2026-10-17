import AppKit
import SwiftUI

/// Sizes of the panel. The panel itself is 820×560 (see RootView).
enum SettingsLayout {
    static let sidebarWidth: CGFloat = 200
    static let contentPadding: CGFloat = 32
    /// Width of the cards in the right column.
    static let contentWidth: CGFloat = 820 - sidebarWidth - contentPadding * 2
}

/// The Settings panel shown over the main window: sections on the left,
/// the selected section on the right.
struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @Binding var section: SettingsSection
    @StateObject private var esc = EscMonitor()

    var body: some View {
        HStack(spacing: 0) {
            SettingsNav(model: model, section: $section)
                .frame(width: SettingsLayout.sidebarWidth)
                .frame(maxHeight: .infinity)
                .background(Color.fxWash)
                .overlay(alignment: .trailing) { Rectangle().fill(Color.fxSeparator).frame(width: 1) }

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(section.label).font(FXFont.pageTitle).foregroundStyle(Color.fxInk)
                    content
                }
                .padding(.horizontal, SettingsLayout.contentPadding)
                .padding(.top, 30)
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(section)  // each section starts scrolled to the top
        }
        .background(Color.fxCard)
        .overlay(alignment: .topTrailing) {
            IconButton(symbol: "xmark", label: "Close settings (esc)", size: 12) { close() }
                .padding(11)
        }
        .onAppear {
            // Esc closes the panel, except while the shortcut recorder is listening.
            esc.monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, !(event.window?.firstResponder is RecorderButton) else { return event }
                close()
                return nil
            }
        }
        .onDisappear {
            if let monitor = esc.monitor { NSEvent.removeMonitor(monitor) }
            esc.monitor = nil
        }
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .general: GeneralSettings(model: model, section: $section)
        case .cloud: CloudSettings(model: model, section: $section)
        case .shortcuts: ShortcutSettings(model: model)
        case .sounds: SoundSettings(model: model)
        case .engine: EngineSettings(model: model)
        case .license: LicenseSettings(model: model)
        case .privacy: PrivacySettings(model: model)
        }
    }

    private func close() {
        model.settingsSection = nil
    }
}

/// The left column: section list and the version footer.
struct SettingsNav: View {
    @ObservedObject var model: AppModel
    @Binding var section: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(text: "Settings").padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(SettingsSection.allCases.filter { !$0.isAccount }) { item($0) }

            Rectangle().fill(Color.fxSeparator).frame(height: 1).padding(.vertical, 10).padding(.horizontal, 8)

            SectionLabel(text: "Account").padding(.horizontal, 8).padding(.bottom, 6)
            ForEach(SettingsSection.allCases.filter(\.isAccount)) { item($0) }

            Spacer()

            HStack {
                Text(version.map { "Foxtation v\($0)" } ?? "Foxtation")
                Spacer()
                Circle().fill(model.cloudOn ? Color.fxGood : Color.fxTrack).frame(width: 6, height: 6)
                Text("Cloud")
            }
            .font(FXFont.caption)
            .foregroundStyle(Color.fxSecondary)
            .padding(.horizontal, 8)
        }
        .padding(.horizontal, 10)
        .padding(.top, 22)
        .padding(.bottom, 16)
    }

    private func item(_ value: SettingsSection) -> some View {
        NavRow(title: value.label, symbol: value.symbol, selected: section == value) { section = value }
    }

    /// nil when not running from an app bundle (debug builds).
    private var version: String? {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    }
}

// MARK: - Shared helpers

/// Holds the panel's Esc key monitor. (`@State` is a macro, so view state lives
/// in small ObservableObjects instead.)
final class EscMonitor: ObservableObject {
    var monitor: Any?
}

extension AppModel {
    /// A binding that writes straight to `settings`; Settings applies side effects itself.
    func setting<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] }, set: { self.settings[keyPath: keyPath] = $0 })
    }
}

/// A compact pop-up menu for the right side of a row.
struct MenuPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var items: [(Value, String)]

    var body: some View {
        Picker("", selection: $selection) {
            ForEach(items.indices, id: \.self) { index in
                Text(items[index].1).tag(items[index].0)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .fixedSize()
    }
}

/// A small note under a card.
struct SettingsNote: View {
    var text: String
    var body: some View {
        Text(text).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// "Active" / "Not activated" capsule.
struct StatusBadge: View {
    var text: String
    var good: Bool

    var body: some View {
        Text(text)
            .font(FXFont.caption.weight(.semibold))
            .foregroundStyle(Color.fxCard)
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Capsule().fill(good ? Color.fxGood : Color.fxSecondary))
    }
}

/// Asks before something that can't be undone. Returns true for the action button.
@MainActor
func confirm(_ title: String, _ message: String, action: String) -> Bool {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = message
    alert.addButton(withTitle: action)
    alert.addButton(withTitle: "Cancel")
    alert.buttons[0].hasDestructiveAction = true
    return alert.runModal() == .alertFirstButtonReturn
}
