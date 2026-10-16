import AppKit
import AVFoundation
import SwiftUI

enum Section: Hashable {
    case home, insights, dictionary, snippets, style, history
}

enum SettingsSection: String, CaseIterable {
    case general, cloud, shortcuts, sounds, engine, advanced, license, privacy

    var title: String {
        switch self {
        case .general: return "General"
        case .cloud: return "Cloud cleanup"
        case .shortcuts: return "Shortcuts"
        case .sounds: return "Sounds"
        case .engine: return "Engine"
        case .advanced: return "Advanced"
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
        case .advanced: return "wrench.and.screwdriver"
        case .license: return "key"
        case .privacy: return "checkmark.shield"
        }
    }
}

enum InsightsRange: Hashable { case days7, days30, all }
enum DictionaryFilter: Hashable { case all, words, replacements }

/// State behind the main window: navigation, the cloud numbers, and the
/// small bits of view state SwiftUI would normally keep in `@State`.
final class AppModel: ObservableObject {

    @Published var section: Section = .home
    /// Non-nil while the Settings sheet is open.
    @Published var settingsSection: SettingsSection?

    @Published var insightsRange: InsightsRange = .days30
    @Published var dictionaryFilter: DictionaryFilter = .all
    @Published var dictionarySearch = ""
    @Published var styleGroup: StyleGroup = .chat
    @Published var showLicenseKey = false
    @Published var keyDraft = ""
    /// "Use another key" swaps the key line for an entry field.
    @Published var enteringKey = false
    @Published var licenseMessage: String?
    @Published var busy = false

    // Foxtation Cloud, as last reported by the server. nil shows "—".
    @Published var usage: CloudUsage?
    @Published var license: LicenseInfo?
    /// The server answered 404 for /v1/license: it predates that endpoint.
    @Published var licenseUnavailable = false

    /// Bumped when MLX / whisper.cpp model state changes so Engine redraws.
    @Published var engineTick = 0
    @Published var playing: UUID?
    @Published var hoveredRow: UUID?

    let settings: Settings
    let library: Library
    /// Re-applies hot keys, recorder limits etc. after a setting changed.
    var onSettingsChanged: () -> Void = {}
    var onStartDictation: () -> Void = {}

    /// Snapshots: fixed clock, no network, no system lookups.
    var snapshotDate: Date?
    var snapshotMicrophone: String?
    var snapshotUserName: String?

    private var player: AVAudioPlayer?

    init(settings: Settings, library: Library) {
        self.settings = settings
        self.library = library
    }

    var now: Date { snapshotDate ?? Date() }

    // MARK: - Small lookups

    var microphoneName: String {
        snapshotMicrophone ?? AVCaptureDevice.default(for: .audio)?.localizedName ?? "No microphone"
    }

    var fullName: String { snapshotUserName ?? NSFullUserName() }

    var firstName: String { fullName.split(separator: " ").first.map(String.init) ?? "" }

    var initials: String {
        let letters = fullName.split(separator: " ").prefix(2).compactMap(\.first)
        return letters.isEmpty ? "🦊" : String(letters).uppercased()
    }

    var greeting: String {
        let hour = Calendar.current.component(.hour, from: now)
        let part = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return firstName.isEmpty ? part : "\(part), \(firstName)"
    }

    /// The key that starts dictation, as shown in key caps.
    var triggerKey: String {
        settings.holdRightOption ? "right ⌥" : HotKey.describe(keyCode: settings.hotKeyCode, modifiers: settings.hotKeyModifiers)
    }

    /// "Hold" when releasing the key pastes, "Press" for the toggle shortcut.
    var triggerVerb: String {
        settings.holdRightOption || settings.triggerMode == .hold ? "Hold" : "Press"
    }

    var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    /// "of 500 · resets 07:00", or dashes before the server reports usage.
    var usageDetail: String {
        guard let usage else { return "of — · resets —" }
        let resets = usage.resetsAt.map { Self.timeFormatter.string(from: $0) } ?? "—"
        return "of \(usage.limit) · resets \(resets)"
    }

    // MARK: - Settings

    /// A binding that writes through to Settings and re-applies settings.
    func binding<T>(_ keyPath: ReferenceWritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.settings[keyPath: keyPath] },
                set: { self.settings[keyPath: keyPath] = $0; self.onSettingsChanged() })
    }

    func openSettings(_ section: SettingsSection = .general) {
        settingsSection = section
        if section == .license { refreshLicense() }
    }

    // MARK: - Foxtation Cloud

    func refreshUsage() {
        guard snapshotDate == nil, !settings.activationID.isEmpty else { return }
        let key = settings.licenseKey, id = settings.activationID
        Task { @MainActor in
            if let usage = try? await CloudCleanup.usage(licenseKey: key, activationID: id) { self.usage = usage }
        }
    }

    func refreshLicense() {
        guard snapshotDate == nil, !settings.activationID.isEmpty else { return }
        let key = settings.licenseKey, id = settings.activationID
        Task { @MainActor in
            do {
                license = try await CloudCleanup.license(licenseKey: key, activationID: id)
                licenseUnavailable = false
            } catch CloudError.notAvailable {
                licenseUnavailable = true
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
        refreshUsage()
    }

    /// Activates this Mac with the key typed into `keyDraft`.
    func activate() {
        let key = keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
        busy = true
        licenseMessage = "Checking…"
        Task { @MainActor in
            defer { busy = false }
            do {
                let id = try await CloudCleanup.activate(key)
                settings.licenseKey = key
                settings.activationID = id
                settings.activatedAt = Date().timeIntervalSince1970
                settings.cloudCleanup = true
                keyDraft = ""
                enteringKey = false
                licenseMessage = nil
                license = nil
                refreshLicense()
            } catch {
                licenseMessage = error.localizedDescription
            }
        }
    }

    func deactivate() {
        let alert = NSAlert()
        alert.messageText = "Deactivate this Mac?"
        alert.informativeText = "Foxtation Cloud stops cleaning up dictations here and frees one activation for another Mac."
        alert.addButton(withTitle: "Deactivate")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        busy = true
        let key = settings.licenseKey, id = settings.activationID
        Task { @MainActor in
            defer { busy = false }
            do {
                try await CloudCleanup.deactivate(licenseKey: key, activationID: id)
            } catch CloudError.notAvailable {
                // The server no longer knows this activation; forget it here too.
            } catch {
                licenseMessage = error.localizedDescription
                return
            }
            settings.activationID = ""
            settings.activatedAt = 0
            license = nil
            usage = nil
            licenseMessage = "This Mac was deactivated."
        }
    }

    // MARK: - History

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func play(_ entry: HistoryEntry) {
        if playing == entry.id {
            player?.stop()
            playing = nil
            return
        }
        guard let url = library.audioURL(entry), let player = try? AVAudioPlayer(contentsOf: url) else { return }
        self.player = player
        player.play()
        playing = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + player.duration + 0.1) { [weak self] in
            if self?.playing == entry.id { self?.playing = nil }
        }
    }

    func exportHistory() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Foxtation history.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try library.exportHistory(to: url)
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    func deleteAllHistory() {
        let alert = NSAlert()
        alert.messageText = "Delete all history?"
        alert.informativeText = "Every saved dictation and recording on this Mac is removed. This can’t be undone."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        library.deleteAllHistory()
    }
}
