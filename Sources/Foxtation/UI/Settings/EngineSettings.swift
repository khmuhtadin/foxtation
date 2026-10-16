import AppKit
import SwiftUI

/// Engine, models and advanced options: the AppKit panes from the old settings
/// window, hosted as they are.
struct EngineSettings: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            PaneView { EnginePane(settings: model.settings, onChange: {}, width: SettingsLayout.contentWidth) }
            PaneView { AdvancedPane(settings: model.settings, onChange: {}, width: SettingsLayout.contentWidth) }
        }
        .frame(width: SettingsLayout.contentWidth, alignment: .leading)
    }
}

/// Hosts an AppKit `Pane`, as tall as its content.
struct PaneView: NSViewRepresentable {
    let make: () -> Pane

    func makeNSView(context: Context) -> PaneHost {
        PaneHost(pane: make())
    }

    func updateNSView(_ host: PaneHost, context: Context) {
        host.pane.reload()
    }
}

final class PaneHost: NSView {
    let pane: Pane

    init(pane: Pane) {
        self.pane = pane
        super.init(frame: .zero)
        pane.translatesAutoresizingMaskIntoConstraints = false
        addSubview(pane)
        NSLayoutConstraint.activate([
            pane.leadingAnchor.constraint(equalTo: leadingAnchor),
            pane.trailingAnchor.constraint(equalTo: trailingAnchor),
            pane.topAnchor.constraint(equalTo: topAnchor),
        ])
        pane.onResize = { [weak self] in self?.invalidateIntrinsicContentSize() }
        pane.reload()
    }

    required init?(coder: NSCoder) { fatalError("not supported") }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: pane.fittingSize.height)
    }
}
