import Foundation

/// Numbers for Home and Insights, worked out from the dictation history.
/// Plain functions over `[Dictation]`; `now` is passed in so snapshots stay stable.
enum Stats {
    static let typingWPM = 40.0

    private static var calendar: Calendar { Calendar.current }

    // MARK: - Picking entries

    static func today(_ entries: [Dictation], now: Date) -> [Dictation] {
        entries.filter { calendar.isDate($0.date, inSameDayAs: now) }
    }

    /// Dictations from the last `days` days, today included. nil keeps everything.
    static func lastDays(_ days: Int?, of entries: [Dictation], now: Date) -> [Dictation] {
        guard let days else { return entries }
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: calendar.startOfDay(for: now))!
        return entries.filter { $0.date >= start }
    }

    // MARK: - Words and time

    static func words(_ entries: [Dictation]) -> Int {
        entries.reduce(0) { $0 + $1.words }
    }

    static func speakingMinutes(_ entries: [Dictation]) -> Double {
        entries.reduce(0) { $0 + $1.seconds } / 60
    }

    /// Words per recorded minute; 0 when nothing was recorded.
    static func wpm(_ entries: [Dictation]) -> Int {
        let minutes = speakingMinutes(entries)
        guard minutes > 0 else { return 0 }
        return Int((Double(words(entries)) / minutes).rounded())
    }

    /// Typing the same words at 40 wpm, minus the time spent speaking. Never negative.
    static func minutesSaved(_ entries: [Dictation]) -> Double {
        max(0, Double(words(entries)) / typingWPM - speakingMinutes(entries))
    }

    // MARK: - Cloud fixes

    static func fixes(_ entries: [Dictation]) -> CloudChanges {
        var sum = CloudChanges()
        for change in entries.compactMap(\.changes) {
            sum.fillersRemoved += change.fillersRemoved
            sum.selfCorrections += change.selfCorrections
            sum.formattingFixes += change.formattingFixes
        }
        return sum
    }

    // MARK: - Mixed Indonesian–English

    private static let indonesianWords: Set<String> = [
        "aku", "kamu", "kita", "kami", "dia", "mereka", "saya", "yang", "dan", "di", "ke", "dari",
        "ini", "itu", "ya", "nggak", "gak", "tidak", "sudah", "udah", "belum", "nanti", "lagi",
        "dulu", "kalau", "sama", "untuk", "buat", "dengan", "juga", "aja", "saja", "ada", "bisa",
        "mau", "siap", "gimana", "bagaimana", "karena", "tapi", "terus", "setelah", "sebelum",
        "minggu", "depan", "jam", "hari", "besok", "kemarin", "tolong", "dong", "deh", "sih", "kok",
    ]

    private static let englishWords: Set<String> = [
        "the", "a", "an", "and", "or", "is", "are", "was", "were", "to", "of", "in", "on", "for",
        "with", "this", "that", "it", "i", "you", "we", "they", "my", "your", "our", "so", "but",
        "if", "not", "be", "have", "has", "do", "at", "by", "from", "as", "will", "can", "just",
        "thanks", "please", "meeting", "deploy", "merge", "review", "update", "sorry", "done",
    ]

    /// Share (0…1) of dictations that use at least one common Indonesian
    /// word and one common English word.
    static func mixedShare(_ entries: [Dictation]) -> Double {
        guard !entries.isEmpty else { return 0 }
        let mixed = entries.filter { dictation in
            let tokens = Set(dictation.text.lowercased().split(whereSeparator: { !$0.isLetter }).map(String.init))
            return !tokens.isDisjoint(with: indonesianWords) && !tokens.isDisjoint(with: englishWords)
        }
        return Double(mixed.count) / Double(entries.count)
    }

    // MARK: - Apps

    struct AppShare: Hashable {
        var app: String
        /// 0…1 of all words in the range.
        var share: Double
        var isOther = false
    }

    /// Share of words per app: the top four, then "Other" for the rest and unknown apps.
    static func byApp(_ entries: [Dictation]) -> [AppShare] {
        let total = words(entries)
        guard total > 0 else { return [] }
        var perApp: [String: Int] = [:]
        var other = 0
        for dictation in entries {
            if dictation.app.isEmpty { other += dictation.words } else { perApp[dictation.app, default: 0] += dictation.words }
        }
        let sorted = perApp.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        var shares = sorted.prefix(4).map { AppShare(app: $0.key, share: Double($0.value) / Double(total)) }
        other += sorted.dropFirst(4).reduce(0) { $0 + $1.value }
        if other > 0 { shares.append(AppShare(app: "Other", share: Double(other) / Double(total), isOther: true)) }
        return shares
    }

    /// Number of different known apps dictated into.
    static func appCount(_ entries: [Dictation]) -> Int {
        Set(entries.map(\.app).filter { !$0.isEmpty }).count
    }

    // MARK: - Days and streaks

    /// Dictations per day, keyed by the start of the day.
    static func dayCounts(_ entries: [Dictation]) -> [Date: Int] {
        var counts: [Date: Int] = [:]
        for dictation in entries { counts[calendar.startOfDay(for: dictation.date), default: 0] += 1 }
        return counts
    }

    /// Consecutive days with a dictation, ending today (or yesterday, if today has none yet).
    static func currentStreak(_ entries: [Dictation], now: Date) -> Int {
        let days = Set(dayCounts(entries).keys)
        var day = calendar.startOfDay(for: now)
        if !days.contains(day) { day = calendar.date(byAdding: .day, value: -1, to: day)! }
        var streak = 0
        while days.contains(day) {
            streak += 1
            day = calendar.date(byAdding: .day, value: -1, to: day)!
        }
        return streak
    }

    static func longestStreak(_ entries: [Dictation]) -> Int {
        var longest = 0
        var run = 0
        var previous: Date?
        for day in dayCounts(entries).keys.sorted() {
            if let previous, calendar.date(byAdding: .day, value: 1, to: previous) == day { run += 1 } else { run = 1 }
            longest = max(longest, run)
            previous = day
        }
        return longest
    }
}
