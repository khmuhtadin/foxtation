import AppKit
import SwiftUI

/// The "Foxtation" window: sidebar with Home, Insights, Dictionary, Snippets
/// and Style, plus Settings as a sheet on top.
final class MainWindow: NSWindow {

    let model: AppModel

    init(model: AppModel) {
        self.model = model
        let size = MainWindow.defaultSize()
        super.init(contentRect: NSRect(origin: .zero, size: size),
                   styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        title = "Foxtation"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        minSize = NSSize(width: 1040, height: 700)
        contentView = NSHostingView(rootView: MainView(model: model, settings: model.settings, library: model.library))
        setContentSize(size)
        center()
        setFrameAutosaveName("FoxtationMain")
    }

    /// The design's 1280×820, shrunk to fit smaller screens.
    private static func defaultSize() -> NSSize {
        let visible = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        return NSSize(width: min(1280, visible.width - 40), height: min(820, visible.height - 40))
    }
}

struct MainView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library

    var body: some View {
        ZStack {
            HStack(spacing: 0) {
                Sidebar(model: model, settings: settings)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Fx.card)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Fx.separator, lineWidth: 1))
                    .padding(.vertical, 10)
                    .padding(.trailing, 10)
            }
            .background(Fx.background)

            if let section = model.settingsSection {
                Color.black.opacity(0.32)
                    .contentShape(Rectangle())
                    .onTapGesture { model.settingsSection = nil }
                SettingsSheet(model: model, settings: settings, library: library, section: section)
            }
        }
        .foregroundStyle(Fx.ink)
        .ignoresSafeArea()
    }

    @ViewBuilder private var content: some View {
        switch model.section {
        case .home: HomeView(model: model, settings: settings, library: library)
        case .history: HistoryView(model: model, library: library)
        case .insights: InsightsView(model: model, library: library)
        case .dictionary: DictionaryView(model: model, settings: settings, library: library)
        case .snippets: SnippetsView(model: model, library: library)
        case .style: StyleView(model: model, library: library)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    static let helpURL = URL(string: "https://github.com/khmuhtadin/foxtation#readme")!

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Room for the traffic lights; snapshots draw stand-ins.
            HStack(spacing: 8) {
                if model.snapshotDate != nil {
                    ForEach([Color(hex: 0xFF5F57), Color(hex: 0xFEBC2E), Color(hex: 0x28C840)], id: \.self) {
                        Circle().fill($0).frame(width: 12, height: 12)
                    }
                }
            }
            .frame(height: 20)
            .padding(.leading, 6)

            HStack(spacing: 10) {
                AppMark(size: 28)
                Text("Foxtation").font(.system(size: 17, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.top, 22)
            .padding(.bottom, 20)

            VStack(spacing: 2) {
                item("Home", "house", .home)
                item("Insights", "chart.bar", .insights)
                item("Dictionary", "book.closed", .dictionary)
                item("Snippets", "text.viewfinder", .snippets)
                item("Style", "textformat", .style)
            }

            Spacer(minLength: 16)

            UsageCard(model: model, settings: settings)
                .padding(.bottom, 10)

            VStack(spacing: 2) {
                NavItem(title: "Settings", symbol: "gearshape", selected: false) { model.openSettings() }
                NavItem(title: "Help", symbol: "questionmark.circle", selected: false) {
                    NSWorkspace.shared.open(Self.helpURL)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(width: 232)
    }

    private func item(_ title: String, _ symbol: String, _ section: Section) -> some View {
        let selected = model.section == section || (section == .home && model.section == .history)
        return NavItem(title: title, symbol: symbol, selected: selected) { model.section = section }
    }
}

struct NavItem: View {
    var title: String
    var symbol: String
    var selected: Bool
    var action: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13))
                .frame(width: 18)
            Text(title).font(.system(size: 13.5, weight: .medium))
            Spacer(minLength: 0)
        }
        .foregroundStyle(selected ? Fx.ink : Fx.ink.opacity(0.78))
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Fx.card : .clear)
            .shadow(color: .black.opacity(selected ? 0.06 : 0), radius: 1, y: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// "Cloud cleanups today 186 of 500 · resets 07:00" with a progress bar.
struct UsageCard: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if settings.activationID.isEmpty {
                Text("Foxtation Cloud").font(.system(size: 12, weight: .medium)).foregroundStyle(Fx.secondary)
                Text("Cleans up filler words, self-corrections and punctuation.")
                    .font(.system(size: 12)).foregroundStyle(Fx.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Add license") { model.openSettings(.license) }
                    .buttonStyle(FxButtonStyle(kind: .plain, height: 26))
            } else {
                HStack {
                    Text("Cloud cleanups today").font(.system(size: 12, weight: .medium)).foregroundStyle(Fx.secondary)
                    Spacer()
                    Text(model.usage.map { "\($0.used)" } ?? "—").font(Fx.mono(12))
                }
                Meter(fraction: model.usage.map { Double($0.used) / Double(max(1, $0.limit)) } ?? 0)
                Text(model.usageDetail).font(.system(size: 12)).foregroundStyle(Fx.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 10)
        .contentShape(Rectangle())
        .onTapGesture { model.openSettings(.license) }
    }
}
