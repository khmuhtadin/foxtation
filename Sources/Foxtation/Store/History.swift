import AppKit
import Combine
import Foundation

/// ~/Library/Application Support/Foxtation
enum AppPaths {
    static let support: URL = {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Foxtation", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()
}

/// One finished dictation, as pasted.
struct Dictation: Codable, Identifiable, Hashable {
    var id = UUID()
    var date: Date
    /// The app it was typed into; empty when unknown.
    var app: String
    var bundleID: String
    /// What Whisper heard.
    var raw: String
    /// What was pasted: after cleanup, replacements and snippets.
    var text: String
    /// Length of the recording in seconds.
    var seconds: Double
    var cloud: Bool
    var changes: CloudChanges?
    /// File name inside the audio folder, when "Keep audio recordings" was on.
    var audio: String?

    var words: Int { Self.wordCount(text) }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }
}

/// Local dictation history: a JSON file plus an optional folder of WAVs.
/// Nothing here ever leaves the Mac.
final class History: ObservableObject {
    static let shared = History(directory: AppPaths.support)

    /// Newest first.
    @Published private(set) var entries: [Dictation] = []

    /// nil keeps everything in memory (samples and snapshots).
    private let directory: URL?

    init(directory: URL?) {
        self.directory = directory
        guard let file = fileURL, let data = try? Data(contentsOf: file) else { return }
        entries = (try? Self.decoder.decode([Dictation].self, from: data)) ?? []
    }

    private var fileURL: URL? { directory?.appendingPathComponent("history.json") }
    var audioDirectory: URL? { directory?.appendingPathComponent("audio", isDirectory: true) }

    // MARK: - Changes

    func add(_ dictation: Dictation, retention: HistoryRetention) {
        guard retention != .off else { return }
        entries.insert(dictation, at: 0)
        prune(retention)
        save()
    }

    func delete(_ id: Dictation.ID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        removeAudio(of: entries[index])
        entries.remove(at: index)
        save()
    }

    func deleteAll() {
        if let audioDirectory { try? FileManager.default.removeItem(at: audioDirectory) }
        entries = []
        save()
    }

    /// Drops entries older than the retention window (all of them for "Don’t keep").
    func prune(_ retention: HistoryRetention) {
        let keep: (Dictation) -> Bool
        switch retention {
        case .off: keep = { _ in false }
        case .forever: keep = { _ in true }
        case .days7, .days30:
            let cutoff = Calendar.current.date(byAdding: .day, value: -(retention.days ?? 0), to: Date())!
            keep = { $0.date >= cutoff }
        }
        let (kept, dropped) = (entries.filter(keep), entries.filter { !keep($0) })
        guard !dropped.isEmpty else { return }
        dropped.forEach(removeAudio)
        entries = kept
        save()
    }

    /// Moves a finished recording into the audio folder and returns its file name.
    func keepAudio(from url: URL, for id: UUID) -> String? {
        guard let audioDirectory else { return nil }
        try? FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        let name = id.uuidString + ".wav"
        do {
            try FileManager.default.copyItem(at: url, to: audioDirectory.appendingPathComponent(name))
            return name
        } catch {
            return nil
        }
    }

    func audioURL(for dictation: Dictation) -> URL? {
        guard let name = dictation.audio, let audioDirectory else { return nil }
        let url = audioDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func export(to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(entries).write(to: url, options: .atomic)
    }

    /// History file plus audio, in bytes.
    var diskBytes: Int64 {
        var total: Int64 = 0
        let manager = FileManager.default
        if let fileURL, let size = try? manager.attributesOfItem(atPath: fileURL.path)[.size] as? Int64 { total += size }
        if let audioDirectory, let files = try? manager.contentsOfDirectory(at: audioDirectory, includingPropertiesForKeys: [.fileSizeKey]) {
            for file in files { total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }

    // MARK: - Storage

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    private func save() {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try? encoder.encode(entries).write(to: fileURL, options: .atomic)
    }

    private func removeAudio(of dictation: Dictation) {
        guard let url = audioURL(for: dictation) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}

extension History {
    /// A believable week of dictations for snapshots and previews.
    static func sample(now: Date = Date()) -> History {
        let history = History(directory: nil)
        let lines: [(String, String, String)] = [
            ("Slack", "com.tinyspeck.slackmacgap", "Oke, aku cek dulu deploy-nya ya. Kalau aman, kita merge sebelum jam tujuh."),
            ("Mail", "com.apple.mail", "Hi team, here's the summary from today's sync. The new onboarding flow ships next Tuesday."),
            ("Cursor", "com.todesktop.230313mzl4w4u92", "Refactor the upload handler so retries use exponential backoff and log the request ID."),
            ("Notes", "com.apple.Notes", "Ide konten minggu depan: tutorial singkat setup automation n8n untuk tim ops."),
            ("WhatsApp", "net.whatsapp.WhatsApp", "Siap, nanti aku kabari lagi setelah meeting. Thanks ya!"),
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        var entries: [Dictation] = []
        // Today: the five lines above at the design's times.
        let times = [(18, 42), (17, 15), (16, 3), (14, 28), (11, 50)]
        for (index, line) in lines.enumerated() {
            let date = calendar.date(bySettingHour: times[index].0, minute: times[index].1, second: 0, of: today)!
            entries.append(Dictation(date: min(date, now), app: line.0, bundleID: line.1,
                                     raw: "eh " + line.2.lowercased(), text: line.2,
                                     seconds: Double(Dictation.wordCount(line.2)) / 2.4, cloud: true,
                                     changes: CloudChanges(fillersRemoved: 2, selfCorrections: index % 2, formattingFixes: 2)))
        }
        // The months before: a few a day on most days, so streaks and the heatmap have shape.
        for day in 1...140 where day % 7 != 3 && day % 11 != 5 {
            let date = calendar.date(byAdding: .day, value: -day, to: today)!
            for k in 0..<(1 + (day * 7) % 6) {
                let line = lines[(day + k) % lines.count]
                let at = calendar.date(byAdding: .minute, value: 9 * 60 + k * 47, to: date)!
                entries.append(Dictation(date: at, app: line.0, bundleID: line.1, raw: line.2, text: line.2,
                                         seconds: Double(Dictation.wordCount(line.2)) / 2.4, cloud: k % 3 != 2,
                                         changes: CloudChanges(fillersRemoved: k % 3, selfCorrections: k % 2, formattingFixes: 1)))
            }
        }
        history.entries = entries.sorted { $0.date > $1.date }
        return history
    }
}
