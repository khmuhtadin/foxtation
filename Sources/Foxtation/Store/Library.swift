import Combine
import Foundation

/// An app Foxtation can recognise by bundle ID.
struct AppRef: Codable, Hashable, Identifiable {
    var bundleID: String
    var name: String
    var id: String { bundleID }
}

/// The kinds of app the Style screen groups by.
enum StyleGroup: String, Codable, CaseIterable, Identifiable {
    case chat, workChat, email, code, notes
    var id: String { rawValue }

    var label: String {
        switch self {
        case .chat: return "Chat"
        case .workChat: return "Work chat"
        case .email: return "Email"
        case .code: return "Code & terminal"
        case .notes: return "Notes & docs"
        }
    }

    var defaultStyle: CleanupStyle {
        switch self {
        case .chat: return .casual
        case .workChat, .notes: return .neutral
        case .email: return .formal
        case .code: return .literal
        }
    }

    /// Styles the group offers. Literal only makes sense for code and terminals.
    var styles: [CleanupStyle] {
        self == .code ? [.casual, .neutral, .formal, .literal] : [.casual, .neutral, .formal]
    }

    var defaultApps: [AppRef] {
        switch self {
        case .chat: return [
            AppRef(bundleID: "net.whatsapp.WhatsApp", name: "WhatsApp"),
            AppRef(bundleID: "ru.keepcoder.Telegram", name: "Telegram"),
            AppRef(bundleID: "com.apple.MobileSMS", name: "Messages"),
            AppRef(bundleID: "com.hnc.Discord", name: "Discord"),
        ]
        case .workChat: return [
            AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack"),
            AppRef(bundleID: "com.microsoft.teams2", name: "Microsoft Teams"),
        ]
        case .email: return [
            AppRef(bundleID: "com.apple.mail", name: "Mail"),
            AppRef(bundleID: "com.microsoft.Outlook", name: "Outlook"),
            AppRef(bundleID: "com.readdle.SparkDesktop", name: "Spark"),
        ]
        case .code: return [
            AppRef(bundleID: "com.apple.dt.Xcode", name: "Xcode"),
            AppRef(bundleID: "com.todesktop.230313mzl4w4u92", name: "Cursor"),
            AppRef(bundleID: "com.microsoft.VSCode", name: "Visual Studio Code"),
            AppRef(bundleID: "com.apple.Terminal", name: "Terminal"),
            AppRef(bundleID: "com.googlecode.iterm2", name: "iTerm2"),
            AppRef(bundleID: "com.mitchellh.ghostty", name: "Ghostty"),
            AppRef(bundleID: "dev.warp.Warp-Stable", name: "Warp"),
        ]
        case .notes: return [
            AppRef(bundleID: "com.apple.Notes", name: "Notes"),
            AppRef(bundleID: "notion.id", name: "Notion"),
            AppRef(bundleID: "md.obsidian", name: "Obsidian"),
            AppRef(bundleID: "com.apple.iWork.Pages", name: "Pages"),
            AppRef(bundleID: "com.microsoft.Word", name: "Word"),
        ]
        }
    }
}

extension CleanupStyle {
    /// The Style screen's names.
    var label: String {
        switch self {
        case .casual: return "Santai"
        case .neutral: return "Netral"
        case .formal: return "Rapi"
        case .literal: return "Literal"
        }
    }

    var detail: String {
        switch self {
        case .casual: return "Lowercase is fine, no trailing period, slang stays."
        case .neutral: return "Normal casing and punctuation, words untouched."
        case .formal: return "Full sentences, standard spelling, no slang."
        case .literal: return "Exactly the spoken words, only fillers removed."
        }
    }

    var example: String {
        switch self {
        case .casual: return "oke gw otw ya, 10 menit lagi sampe"
        case .neutral: return "Oke, gw otw ya. 10 menit lagi sampe."
        case .formal: return "Oke, saya sedang di jalan. Sekitar 10 menit lagi sampai."
        case .literal: return "git commit dash m fix upload retry"
        }
    }
}

enum TermCategory: String, Codable, CaseIterable, Identifiable {
    case name, company, product, tool, other
    var id: String { rawValue }
    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// A word Foxtation must spell exactly. Sent to the cloud as vocabulary.
struct Term: Codable, Hashable, Identifiable {
    var id = UUID()
    var text: String
    var category: TermCategory
}

/// A deterministic swap applied on the Mac after cleanup.
struct Replacement: Codable, Hashable, Identifiable {
    var id = UUID()
    var from: String
    var to: String
    /// nil = all apps.
    var scope: StyleGroup?

    var scopeLabel: String { scope.map { "\($0.label) only" } ?? "All apps" }
}

/// Saved text dropped in when its cue is spoken.
struct Snippet: Codable, Hashable, Identifiable {
    var id = UUID()
    var cue: String
    var text: String
    var used = 0
}

struct GroupStyle: Codable, Hashable {
    var style: CleanupStyle
    var apps: [AppRef]
}

/// The user's dictionary, snippets and per-app styles, in library.json.
final class Library: ObservableObject {
    static let shared = Library(directory: AppPaths.support)

    @Published var terms: [Term] = [] { didSet { save() } }
    @Published var replacements: [Replacement] = [] { didSet { save() } }
    @Published var snippets: [Snippet] = [] { didSet { save() } }
    @Published var groups: [StyleGroup: GroupStyle] = Library.defaultGroups { didSet { save() } }
    @Published var spokenEmoji = true { didSet { save() } }
    /// Suggestions the user dismissed, lowercased.
    @Published var dismissedSuggestions: [String] = [] { didSet { save() } }

    private let directory: URL?
    private var loading = false

    static var defaultGroups: [StyleGroup: GroupStyle] {
        Dictionary(uniqueKeysWithValues: StyleGroup.allCases.map { ($0, GroupStyle(style: $0.defaultStyle, apps: $0.defaultApps)) })
    }

    init(directory: URL?) {
        self.directory = directory
        guard let file = fileURL, let data = try? Data(contentsOf: file),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else { return }
        loading = true
        terms = stored.terms
        replacements = stored.replacements
        snippets = stored.snippets
        groups = Self.defaultGroups.merging(stored.groups) { _, saved in saved }
        spokenEmoji = stored.spokenEmoji
        dismissedSuggestions = stored.dismissedSuggestions
        loading = false
    }

    // MARK: - Lookups used while dictating

    func group(forBundleID bundleID: String) -> StyleGroup? {
        StyleGroup.allCases.first { groups[$0]?.apps.contains { $0.bundleID == bundleID } == true }
    }

    func style(forBundleID bundleID: String) -> CleanupStyle? {
        group(forBundleID: bundleID).flatMap { groups[$0]?.style }
    }

    var vocabulary: [String] { terms.map(\.text) }
    var snippetCues: [String] { snippets.map(\.cue) }

    /// Whole-word, case-insensitive swaps for the target app's group.
    func applyReplacements(_ text: String, group: StyleGroup?) -> String {
        var result = text
        for replacement in replacements where replacement.scope == nil || replacement.scope == group {
            let from = replacement.from.trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            result = Self.replacingPhrase(from, with: replacement.to, in: result)
        }
        return result
    }

    /// Replaces every spoken cue with its snippet and counts each use.
    func expandSnippets(_ text: String) -> String {
        var result = text
        for index in snippets.indices {
            let cue = snippets[index].cue.trimmingCharacters(in: .whitespaces)
            guard !cue.isEmpty else { continue }
            let expanded = Self.replacingPhrase(cue, with: snippets[index].text, in: result)
            if expanded != result {
                snippets[index].used += 1
                result = expanded
            }
        }
        return result
    }

    /// Capitalized or mixed-case words seen at least twice in history that
    /// aren't in the dictionary yet. Most frequent first.
    func suggestions(from history: [Dictation], limit: Int = 4) -> [String] {
        let known = Set(terms.map { $0.text.lowercased() } + dismissedSuggestions)
        var counts: [String: Int] = [:]
        for entry in history.prefix(500) {
            // A capital at the start of a sentence says nothing; elsewhere it marks a name.
            for sentence in entry.text.split(whereSeparator: { ".!?\n:".contains($0) }) {
                let words = sentence.split(whereSeparator: { !$0.isLetter && !$0.isNumber && $0 != "-" })
                for (index, raw) in words.enumerated() {
                    let word = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: "-"))
                    guard word.count >= 3 else { continue }
                    let mixedCase = word.dropFirst().contains(where: \.isUppercase)
                        || (word.contains(where: \.isNumber) && word.contains(where: \.isLetter))
                    let capitalized = word.first?.isUppercase == true && index > 0
                    guard mixedCase || capitalized, !known.contains(word.lowercased()) else { continue }
                    counts[word, default: 0] += 1
                }
            }
        }
        return counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map(\.key)
    }

    /// Case-insensitive whole-phrase replacement.
    static func replacingPhrase(_ phrase: String, with replacement: String, in text: String) -> String {
        let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range,
                                              withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
    }

    // MARK: - Storage

    private struct Stored: Codable {
        var terms: [Term]
        var replacements: [Replacement]
        var snippets: [Snippet]
        var groups: [StyleGroup: GroupStyle]
        var spokenEmoji: Bool
        var dismissedSuggestions: [String]
    }

    private var fileURL: URL? { directory?.appendingPathComponent("library.json") }

    private func save() {
        guard !loading, let fileURL else { return }
        let stored = Stored(terms: terms, replacements: replacements, snippets: snippets, groups: groups,
                            spokenEmoji: spokenEmoji, dismissedSuggestions: dismissedSuggestions)
        try? JSONEncoder().encode(stored).write(to: fileURL, options: .atomic)
    }
}

extension Library {
    /// The design's sample dictionary and snippets.
    static func sample() -> Library {
        let library = Library(directory: nil)
        library.terms = [
            Term(text: "Khairul Muhtadin", category: .name),
            Term(text: "Jakmall", category: .company),
            Term(text: "Foxtation", category: .product),
            Term(text: "n8n", category: .tool),
            Term(text: "Khaisa Studio", category: .company),
        ]
        library.replacements = [
            Replacement(from: "gimana", to: "bagaimana", scope: .email),
            Replacement(from: "btw", to: "by the way", scope: nil),
        ]
        library.snippets = [
            Snippet(cue: "my email", text: "[YOUR EMAIL]", used: 48),
            Snippet(cue: "standup", text: "Kemarin: … Hari ini: … Blocker: …", used: 31),
            Snippet(cue: "polish prompt", text: "Rewrite this to be clearer and shorter. Keep my tone and keep Indonesian–English as is.", used: 22),
            Snippet(cue: "alamat kantor", text: "[YOUR OFFICE ADDRESS]", used: 9),
            Snippet(cue: "my calendar", text: "[YOUR BOOKING LINK]", used: 4),
        ]
        return library
    }
}
