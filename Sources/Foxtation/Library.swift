import AppKit
import Foundation

// MARK: - Records

/// One finished dictation, kept on this Mac only.
struct HistoryEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var appName: String
    var bundleID: String
    /// What the speech engine heard.
    var raw: String
    /// What was pasted.
    var final: String
    var words: Int
    /// Length of the recording in seconds.
    var seconds: Double
    var cloudUsed: Bool
    var changes: CleanupChanges?
    /// File name inside the audio folder when "Keep audio recordings" is on.
    var audioFile: String?
}

enum WordCategory: String, Codable, CaseIterable {
    case name, company, product, tool, other
    var label: String { rawValue.capitalized }
}

/// A word Foxtation should spell exactly, or (when `from` is set) a
/// replacement applied to the text before pasting.
struct DictionaryEntry: Codable, Identifiable {
    var id = UUID()
    var text: String
    var category: WordCategory = .other
    var from = ""
    /// nil means every app; otherwise only apps in this style group.
    var scope: StyleGroup?

    var isReplacement: Bool { !from.isEmpty }
}

struct Snippet: Codable, Identifiable {
    var id = UUID()
    var cue: String
    var expansion: String
    var used = 0
}

enum StyleGroup: String, Codable, CaseIterable {
    case chat, workChat, email, code, notes
    var label: String {
        switch self {
        case .chat: return "Chat"
        case .workChat: return "Work chat"
        case .email: return "Email"
        case .code: return "Code & terminal"
        case .notes: return "Notes & docs"
        }
    }
}

/// The values match what Foxtation Cloud accepts as `style`.
enum Tone: String, Codable, CaseIterable {
    case casual, neutral, formal, literal
    var label: String {
        switch self {
        case .casual: return "Santai"
        case .neutral: return "Netral"
        case .formal: return "Rapi"
        case .literal: return "Literal"
        }
    }
}

struct AppRef: Codable, Hashable {
    var bundleID: String
    var name: String
}

struct GroupStyle: Codable {
    var group: StyleGroup
    var tone: Tone
    var apps: [AppRef]
}

struct StyleSettings: Codable {
    var groups: [GroupStyle]
    var spokenEmoji = false

    static let defaults = StyleSettings(groups: [
        GroupStyle(group: .chat, tone: .casual, apps: [
            AppRef(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
            AppRef(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
            AppRef(bundleID: "com.apple.MobileSMS", name: "Messages"),
            AppRef(bundleID: "com.hnc.Discord", name: "Discord"),
        ]),
        GroupStyle(group: .workChat, tone: .neutral, apps: [
            AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            AppRef(bundleID: "com.microsoft.teams2", name: "Teams"),
        ]),
        GroupStyle(group: .email, tone: .formal, apps: [
            AppRef(bundleID: "com.apple.mail", name: "Mail"),
            AppRef(bundleID: "com.microsoft.Outlook", name: "Outlook"),
            AppRef(bundleID: "com.readdle.SparkDesktop", name: "Spark"),
        ]),
        GroupStyle(group: .code, tone: .literal, apps: [
            AppRef(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            AppRef(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
            AppRef(bundleID: "com.microsoft.VSCode", name: "VS Code"),
            AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
            AppRef(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
            AppRef(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
            AppRef(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        ]),
        GroupStyle(group: .notes, tone: .neutral, apps: [
            AppRef(bundleID: "com.apple.Notes", name: "Notes"),
            AppRef(bundleID: "notion.id", name: "Notion"),
            AppRef(bundleID: "md.obsidian", name: "Obsidian"),
            AppRef(bundleID: "com.apple.iWork.Pages", name: "Pages"),
            AppRef(bundleID: "com.microsoft.Word", name: "Word"),
        ]),
    ])

    func group(for bundleID: String) -> StyleGroup? {
        groups.first { $0.apps.contains { $0.bundleID == bundleID } }?.group
    }

    func style(_ group: StyleGroup) -> GroupStyle {
        groups.first { $0.group == group } ?? GroupStyle(group: group, tone: .neutral, apps: [])
    }
}

// MARK: - Store

/// Everything the app keeps besides preferences: history, dictionary,
/// snippets and per-app styles. Each list is a JSON file in
/// ~/Library/Application Support/Foxtation/.
final class Library: ObservableObject {

    static let shared = Library()

    @Published var history: [HistoryEntry] = []
    @Published var dictionary: [DictionaryEntry] = []
    @Published var snippets: [Snippet] = []
    @Published var styles = StyleSettings.defaults

    let folder: URL
    var audioFolder: URL { folder.appendingPathComponent("audio", isDirectory: true) }

    /// Snapshots use sample data and must never touch the user's files.
    private var savesToDisk = true

    init(folder: URL? = nil) {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.folder = folder ?? support.appendingPathComponent("Foxtation", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true)
        history = load("history.json") ?? []
        dictionary = load("dictionary.json") ?? []
        snippets = load("snippets.json") ?? []
        styles = load("styles.json") ?? StyleSettings.defaults
    }

    static func sample(_ build: (Library) -> Void) -> Library {
        let library = Library(folder: FileManager.default.temporaryDirectory.appendingPathComponent("FoxtationSample"))
        library.savesToDisk = false
        library.history = []
        library.dictionary = []
        library.snippets = []
        library.styles = .defaults
        build(library)
        return library
    }

    // MARK: History

    func add(_ entry: HistoryEntry) {
        history.insert(entry, at: 0)
        save(history, "history.json")
    }

    func delete(_ entry: HistoryEntry) {
        if let file = entry.audioFile { try? FileManager.default.removeItem(at: audioFolder.appendingPathComponent(file)) }
        history.removeAll { $0.id == entry.id }
        save(history, "history.json")
    }

    func deleteAllHistory() {
        try? FileManager.default.removeItem(at: audioFolder)
        history = []
        save(history, "history.json")
    }

    /// Drops entries older than the retention window, with their audio.
    func prune(_ retention: HistoryRetention) {
        guard let days = retention.days else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let old = history.filter { $0.date < cutoff }
        guard !old.isEmpty else { return }
        for entry in old {
            if let file = entry.audioFile { try? FileManager.default.removeItem(at: audioFolder.appendingPathComponent(file)) }
        }
        history.removeAll { $0.date < cutoff }
        save(history, "history.json")
    }

    func audioURL(_ entry: HistoryEntry) -> URL? {
        guard let file = entry.audioFile else { return nil }
        let url = audioFolder.appendingPathComponent(file)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Bytes used by history.json plus kept audio.
    func diskUsage() -> Int {
        guard savesToDisk else { return (try? JSONEncoder().encode(history).count) ?? 0 }
        var total = 0
        let files = [folder.appendingPathComponent("history.json")]
            + ((try? FileManager.default.contentsOfDirectory(at: audioFolder, includingPropertiesForKeys: nil)) ?? [])
        for file in files {
            total += (try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        return total
    }

    func exportHistory(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(history).write(to: url)
    }

    // MARK: Dictionary, snippets, styles

    func saveDictionary() { save(dictionary, "dictionary.json") }
    func saveSnippets() { save(snippets, "snippets.json") }
    func saveStyles() { save(styles, "styles.json") }

    func setTone(_ tone: Tone, for group: StyleGroup) {
        guard let index = styles.groups.firstIndex(where: { $0.group == group }) else { return }
        styles.groups[index].tone = tone
        saveStyles()
    }

    /// Moves the app into `group`; an app belongs to one group at most.
    func addApp(_ app: AppRef, to group: StyleGroup) {
        for index in styles.groups.indices {
            styles.groups[index].apps.removeAll { $0.bundleID == app.bundleID }
        }
        guard let index = styles.groups.firstIndex(where: { $0.group == group }) else { return }
        styles.groups[index].apps.append(app)
        saveStyles()
    }

    func removeApp(_ app: AppRef, from group: StyleGroup) {
        guard let index = styles.groups.firstIndex(where: { $0.group == group }) else { return }
        styles.groups[index].apps.removeAll { $0.bundleID == app.bundleID }
        saveStyles()
    }

    // MARK: Files

    private func load<T: Decodable>(_ name: String) -> T? {
        guard let data = try? Data(contentsOf: folder.appendingPathComponent(name)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            NSLog("Foxtation: could not read %@: %@", name, error.localizedDescription)
            return nil
        }
    }

    private func save<T: Encodable>(_ value: T, _ name: String) {
        guard savesToDisk else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(value).write(to: folder.appendingPathComponent(name), options: .atomic)
        } catch {
            NSLog("Foxtation: could not write %@: %@", name, error.localizedDescription)
        }
    }
}
