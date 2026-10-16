import SwiftUI

/// The Settings panel shown over the main window.
struct SettingsPanel: View {
    @ObservedObject var model: AppModel
    @Binding var section: SettingsSection

    var body: some View {
        PagePlaceholder(title: section.label).padding(24)
    }
}
