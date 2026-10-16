import Foundation

/// Local text rules applied right before pasting, with or without Foxtation Cloud.
enum TextRules {

    /// Applies the dictionary's replacements that fit `group`, then expands
    /// snippet cues. Returns the new text and how often each snippet fired.
    static func apply(_ text: String, dictionary: [DictionaryEntry], snippets: [Snippet],
                      group: StyleGroup?) -> (text: String, used: [UUID: Int]) {
        var result = text
        for entry in dictionary where entry.isReplacement && (entry.scope == nil || entry.scope == group) {
            result = replace(entry.from, with: entry.text, in: result).text
        }
        var used: [UUID: Int] = [:]
        for snippet in snippets where !snippet.cue.isEmpty {
            let replaced = replace(snippet.cue, with: snippet.expansion, in: result)
            result = replaced.text
            if replaced.count > 0 { used[snippet.id] = replaced.count }
        }
        return (result, used)
    }

    /// Whole-word, case-insensitive replacement. Spaces in `phrase` match any run of whitespace.
    static func replace(_ phrase: String, with replacement: String, in text: String) -> (text: String, count: Int) {
        let words = phrase.split(whereSeparator: \.isWhitespace).map { NSRegularExpression.escapedPattern(for: String($0)) }
        guard !words.isEmpty else { return (text, 0) }
        let pattern = "(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return (text, 0) }
        let range = NSRange(text.startIndex..., in: text)
        let count = regex.numberOfMatches(in: text, range: range)
        guard count > 0 else { return (text, 0) }
        let output = regex.stringByReplacingMatches(in: text, range: range,
                                                    withTemplate: NSRegularExpression.escapedTemplate(for: replacement))
        return (output, count)
    }

    static func wordCount(_ text: String) -> Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    /// Words for the cloud `vocabulary`: 1–64 characters, at most 300.
    static func vocabulary(_ dictionary: [DictionaryEntry]) -> [String] {
        let words = dictionary.filter { !$0.isReplacement }.map { $0.text.trimmingCharacters(in: .whitespaces) }
        return Array(words.filter { (1...64).contains($0.count) }.prefix(300))
    }

    /// Cues for the cloud `snippet_cues`: 1–64 characters, at most 100.
    static func snippetCues(_ snippets: [Snippet]) -> [String] {
        let cues = snippets.map { $0.cue.trimmingCharacters(in: .whitespaces) }
        return Array(cues.filter { (1...64).contains($0.count) }.prefix(100))
    }

    // MARK: - Language mix

    private static let indonesian: Set<String> = [
        "yang", "dan", "di", "ke", "dari", "ini", "itu", "aku", "saya", "kamu", "kita", "kami", "ya", "nggak",
        "gak", "tidak", "sudah", "udah", "belum", "akan", "mau", "bisa", "ada", "dengan", "untuk", "tapi",
        "jadi", "kalau", "lagi", "dulu", "nanti", "juga", "aja", "saja", "sama", "gimana", "bagaimana", "kenapa",
    ]
    private static let english: Set<String> = [
        "the", "and", "is", "are", "to", "of", "in", "it", "that", "this", "with", "for", "you", "we", "i",
        "be", "was", "will", "have", "has", "not", "but", "so", "can", "just", "then", "what", "how",
    ]

    /// True when the text has both Indonesian and English function words.
    static func isMixedIndonesianEnglish(_ text: String) -> Bool {
        let words = Set(text.lowercased().split { !$0.isLetter }.map(String.init))
        return !words.isDisjoint(with: indonesian) && !words.isDisjoint(with: english)
    }

    // MARK: - Dictionary suggestions

    /// Capitalized (not starting a sentence) or mixed-case words seen at least
    /// twice in history and not in the dictionary yet, most frequent first.
    /// Neighbouring capitalized words count as one phrase ("Durable Object").
    static func suggestions(history: [HistoryEntry], dictionary: [DictionaryEntry], limit: Int = 6) -> [String] {
        let known = Set(dictionary.flatMap { [$0.text.lowercased(), $0.from.lowercased()] })
        var counts: [String: Int] = [:]
        for entry in history {
            var sentenceStart = true
            var run: [String] = []
            func flush() {
                let phrase = run.joined(separator: " ")
                if !run.isEmpty, !known.contains(phrase.lowercased()) { counts[phrase, default: 0] += 1 }
                run = []
            }
            for token in entry.final.split(whereSeparator: \.isWhitespace) {
                let word = token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
                let endsClause = token.last.map { ".!?:,;\n".contains($0) } ?? false
                let plain = word.count >= 3 && word.allSatisfy { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }
                let mixedCase = word.dropFirst().contains(where: \.isUppercase) && word.contains(where: \.isLowercase)
                let capitalized = (word.first?.isUppercase ?? false) && !sentenceStart
                if plain && (mixedCase || capitalized) { run.append(word) } else { flush() }
                if endsClause { flush() }
                sentenceStart = token.last.map { ".!?:\n".contains($0) } ?? false
            }
            flush()
        }
        return counts.filter { $0.value >= 2 }
            .sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
            .prefix(limit).map(\.key)
    }
}

// MARK: - Stats

/// Numbers shown on Home and Insights, all computed from local history.
struct Stats {
    static let typingWPM = 40.0

    var words = 0
    var seconds = 0.0
    var dictations = 0
    var fillers = 0
    var corrections = 0
    var formatting = 0
    var mixed = 0

    init(_ entries: [HistoryEntry]) {
        for entry in entries {
            words += entry.words
            seconds += entry.seconds
            dictations += 1
            fillers += entry.changes?.fillers_removed ?? 0
            corrections += entry.changes?.self_corrections ?? 0
            formatting += entry.changes?.formatting_fixes ?? 0
            if TextRules.isMixedIndonesianEnglish(entry.final) { mixed += 1 }
        }
    }

    var wpm: Int { seconds > 1 ? Int((Double(words) / seconds * 60).rounded()) : 0 }
    var fixes: Int { fillers + corrections + formatting }
    var mixedPercent: Int { dictations > 0 ? Int((Double(mixed) / Double(dictations) * 100).rounded()) : 0 }

    /// Typing the same words at 40 wpm, minus the time spent speaking.
    var minutesSaved: Int { max(0, Int((Double(words) / Self.typingWPM - seconds / 60).rounded())) }

    static func hoursAndMinutes(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(String(format: "%02d", minutes % 60))m" : "\(minutes)m"
    }

    /// Share of words per app: the top four, then everything else as "Other".
    static func byApp(_ entries: [HistoryEntry]) -> (rows: [(name: String, share: Double)], apps: Int) {
        var words: [String: Int] = [:]
        for entry in entries { words[entry.appName.isEmpty ? "Unknown" : entry.appName, default: 0] += max(1, entry.words) }
        let total = Double(words.values.reduce(0, +))
        guard total > 0 else { return ([], 0) }
        let sorted = words.sorted { $0.value > $1.value }
        var rows = sorted.prefix(4).map { (name: $0.key, share: Double($0.value) / total) }
        let rest = sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        if rest > 0 { rows.append((name: "Other", share: Double(rest) / total)) }
        return (rows, words.count)
    }

    /// Dictations per calendar day.
    static func perDay(_ entries: [HistoryEntry], calendar: Calendar = .current) -> [Date: Int] {
        var days: [Date: Int] = [:]
        for entry in entries { days[calendar.startOfDay(for: entry.date), default: 0] += 1 }
        return days
    }

    /// Days in a row with a dictation, ending today (or yesterday, so the
    /// streak isn't lost before the first dictation of the day).
    static func streak(_ days: [Date: Int], today: Date = Date(), calendar: Calendar = .current) -> Int {
        var day = calendar.startOfDay(for: today)
        if days[day] == nil { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var count = 0
        while days[day] != nil {
            count += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return count
    }

    static func longestStreak(_ days: [Date: Int], calendar: Calendar = .current) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in days.keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}
