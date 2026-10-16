import AppKit
import AVFoundation
import Combine
import SwiftUI

enum Page: Hashable {
    case home, history, insights, dictionary, snippets, style
}

enum SettingsSection: String, CaseIterable, Identifiable {
    case general, cloud, shortcuts, sounds, engine, license, privacy
    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return "General"
        case .cloud: return "Cloud cleanup"
        case .shortcuts: return "Shortcuts"
        case .sounds: return "Sounds"
        case .engine: return "Engine"
        case .license: return "License"
        case .privacy: return "Data & Privacy"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "slider.horizontal.3"
        case .cloud: return "sparkles"
        case .shortcuts: return "keyboard"
        case .sounds: return "speaker.wave.2"
        case .engine: return "cpu"
        case .license: return "key"
        case .privacy: return "checkmark.shield"
        }
    }

    /// Account sections are listed under their own heading.
    var isAccount: Bool { self == .license || self == .privacy }
}

/// Everything the main window shows and the actions it can take. Screens read
/// the stores directly; AppDelegate wires the actions.
final class AppModel: ObservableObject {
    let settings: Settings
    let history: History
    let library: Library
    let cloud: CloudStatus

    @Published var page: Page = .home
    /// Non-nil while the Settings panel is open over the window.
    @Published var settingsSection: SettingsSection?

    /// Starts (or stops) a dictation, as the hot key would.
    var startDictation: () -> Void = {}
    /// Re-applies settings that need side effects (hot key, launch at login…).
    var settingsChanged: () -> Void = {}
    /// Snapshots pin the clock so they render the same every time.
    var now: () -> Date = { Date() }
    let isSnapshot: Bool

    private var forward: [AnyCancellable] = []

    init(settings: Settings, history: History, library: Library, cloud: CloudStatus, isSnapshot: Bool = false) {
        self.settings = settings
        self.history = history
        self.library = library
        self.cloud = cloud
        self.isSnapshot = isSnapshot
        // One observable for the views: any store change redraws the window.
        for publisher in [settings.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                          history.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                          library.objectWillChange.map { _ in () }.eraseToAnyPublisher(),
                          cloud.objectWillChange.map { _ in () }.eraseToAnyPublisher()] {
            forward.append(publisher.sink { [weak self] in self?.objectWillChange.send() })
        }
    }

    /// "right ⌥" or the configured shortcut, for "Hold … to dictate".
    var triggerKey: String {
        settings.holdRightOption ? "right ⌥" : HotKey.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    var microphoneName: String {
        if isSnapshot { return "MacBook Pro Microphone" }
        return AVCaptureDevice.default(for: .audio)?.localizedName ?? "No microphone"
    }

    var userName: String {
        isSnapshot ? "Khairul Muhtadin" : NSFullUserName()
    }

    var cloudOn: Bool { settings.cloudCleanup && !settings.activationID.isEmpty }

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
    }
}

extension AppModel {
    /// Sample data matching the design boards, for `--render-window`.
    static func sample() -> AppModel {
        let settings = Settings.shared
        settings.persistsChanges = false
        settings.licenseKey = "FOXTATION-89151850-3349-4A1A-9035-E56FDA79A59C"
        settings.activationID = "sample-activation"
        settings.cloudCleanup = true
        let cloud = CloudStatus(settings: settings)
        cloud.usage = CloudUsage(used: 186, limit: 500, resetsAt: "2026-10-17T00:00:00.000Z")
        cloud.license = CloudLicense(status: "granted", displayKey: "****-79A59C", expiresAt: nil,
                                     activations: .init(used: nil, limit: 3),
                                     thisDevice: .init(activationId: "sample-activation", label: "MacBook Pro",
                                                       createdAt: "2026-10-12T09:20:00Z"),
                                     portalUrl: CloudCleanup.portalURL.absoluteString)
        let fixed = Calendar.current.date(bySettingHour: 19, minute: 5, second: 0, of: Date())!
        let model = AppModel(settings: settings, history: .sample(now: fixed), library: .sample(),
                             cloud: cloud, isSnapshot: true)
        model.now = { fixed }
        return model
    }
}

// MARK: - Window

final class MainWindowController {
    let model: AppModel
    private(set) lazy var window: NSWindow = makeWindow()

    init(model: AppModel) {
        self.model = model
    }

    func show(_ page: Page? = nil, settings section: SettingsSection? = nil) {
        if let page { model.page = page }
        if let section { model.settingsSection = section }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        Task { await model.cloud.refresh() }
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1180, height: 780),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Foxtation"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 980, height: 640)
        window.backgroundColor = Palette.background
        window.contentView = NSHostingView(rootView: RootView(model: model))
        window.center()
        window.setFrameAutosaveName("FoxtationMain")
        return window
    }
}

// MARK: - Root

struct RootView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model)
                .frame(width: 220)
            content
                .padding(.horizontal, 36)
                .padding(.top, 30)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(RoundedRectangle(cornerRadius: 12).fill(Color.fxCard))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.fxSeparator))
                .padding(.vertical, 10)
                .padding(.trailing, 10)
        }
        .background(Color.fxBackground)
        .overlay {
            if let section = model.settingsSection {
                ZStack {
                    Color.black.opacity(0.28)
                        .onTapGesture { model.settingsSection = nil }
                    SettingsPanel(model: model, section: Binding(get: { section }, set: { model.settingsSection = $0 }))
                        .frame(width: 820, height: 560)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.fxCard))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: .black.opacity(0.25), radius: 30, y: 12)
                }
            }
        }
        .foregroundStyle(Color.fxInk)
    }

    @ViewBuilder private var content: some View {
        switch model.page {
        case .home: HomePage(model: model)
        case .history: HistoryPage(model: model)
        case .insights: InsightsPage(model: model)
        case .dictionary: DictionaryPage(model: model)
        case .snippets: SnippetsPage(model: model)
        case .style: StylePage(model: model)
        }
    }
}

// MARK: - Sidebar

struct Sidebar: View {
    @ObservedObject var model: AppModel

    private let items: [(Page, String, String)] = [
        (.home, "Home", "house"),
        (.insights, "Insights", "chart.bar"),
        (.dictionary, "Dictionary", "book.closed"),
        (.snippets, "Snippets", "text.badge.plus"),
        (.style, "Style", "textformat"),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                Image(nsImage: NSApp.applicationIconImage ?? NSImage())
                    .resizable().frame(width: 26, height: 26)
                Text("Foxtation").font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 6)
            .padding(.top, 38)  // below the traffic lights
            .padding(.bottom, 18)

            ForEach(items, id: \.0) { page, title, symbol in
                item(title, symbol, selected: model.page == page || (page == .home && model.page == .history)) {
                    model.page = page
                }
            }

            Spacer()

            UsageCard(model: model)
                .padding(.bottom, 10)
            item("Settings", "gearshape", selected: false) { model.openSettings() }
            item("Help", "questionmark.circle", selected: false) {
                NSWorkspace.shared.open(URL(string: "https://github.com/khmuhtadin/foxtation#readme")!)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
    }

    private func item(_ title: String, _ symbol: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol).frame(width: 16).foregroundStyle(selected ? Color.fxInk : Color.fxSecondary)
                Text(title).font(FXFont.body.weight(selected ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 7).fill(selected ? Color.fxCard : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// "Cloud cleanups today 186 of 500 · resets 07:00", or a nudge to get a license.
struct UsageCard: View {
    @ObservedObject var model: AppModel

    var body: some View {
        FXCard(padding: 10) {
            if let usage = model.cloud.usage, model.cloudOn {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Cloud cleanups today").font(FXFont.caption)
                        Spacer()
                        Text("\(usage.used)").font(FXFont.caption.weight(.semibold)).monospacedDigit()
                    }
                    UsageBar(fraction: Double(usage.used) / Double(max(1, usage.limit)))
                    Text("of \(usage.limit) · resets \(usage.resetDate.map(Format.time) ?? "—")")
                        .font(FXFont.caption).foregroundStyle(Color.fxSecondary)
                }
            } else if model.cloudOn {
                Text("Cloud cleanup on").font(FXFont.caption)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Foxtation Cloud").font(FXFont.caption.weight(.semibold))
                    Text("Clean, punctuated text in your style.").font(FXFont.caption).foregroundStyle(Color.fxSecondary)
                    Button("Set up") { model.openSettings(.license) }.fxButton(.secondary, compact: true)
                }
            }
        }
    }
}
