import AppKit
import SwiftUI

/// Hidden: `Foxtation --render-window <dir>` writes every screen of the main
/// window and every pill state to PNG, light and dark, using sample data.
/// Nothing is read from or written to the user's history or preferences.
enum WindowSnapshots {

    static let size = CGSize(width: 1280, height: 820)

    @MainActor
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let model = sampleModel()

        let screens: [(String, Section, SettingsSection?)] = [
            ("1-home", .home, nil),
            ("1b-history", .history, nil),
            ("2-insights", .insights, nil),
            ("3-dictionary", .dictionary, nil),
            ("4-snippets", .snippets, nil),
            ("5-style", .style, nil),
            ("6-settings-general", .home, .general),
            ("6b-settings-cloud", .home, .cloud),
            ("6c-settings-shortcuts", .home, .shortcuts),
            ("6d-settings-sounds", .home, .sounds),
            ("6e-settings-engine", .home, .engine),
            ("6f-settings-advanced", .home, .advanced),
            ("7-settings-license", .home, .license),
            ("8-settings-privacy", .home, .privacy),
        ]
        for (name, section, settingsSection) in screens {
            model.section = section
            model.settingsSection = settingsSection
            for dark in [false, true] {
                let view = MainView(model: model, settings: model.settings, library: model.library)
                try write(view, size: size, dark: dark, to: directory.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
            }
        }

        // The pill on its own, one state per file.
        let pills: [(String, HUDState, String, String)] = [
            ("listening", .listening, "Listening", ""),
            ("transcribing", .processing, "Transcribing…", ""),
            ("cleaning", .processing, "Cleaning up for", "Slack"),
            ("pasted", .success, "Pasted", "· 24 words"),
            ("fallback-limit", .fallback, "Daily limit reached", "· raw text pasted"),
            ("fallback-offline", .fallback, "Offline", "· raw text pasted"),
            ("fallback-license", .fallback, "License problem", "· raw text pasted"),
        ]
        for dark in [false, true] {
            let sheet = VStack(alignment: .leading, spacing: 18) {
                ForEach(pills, id: \.0) { name, state, label, detail in
                    HStack(spacing: 20) {
                        PillView(model: HUDModel.snapshot(state, label: label, detail: detail))
                        Text(name).font(.system(size: 13, weight: .medium))
                            .foregroundStyle(dark ? Color.white.opacity(0.7) : Color(hex: 0x1E2140))
                    }
                }
            }
            .padding(32)
            .background(dark ? Color(hex: 0x151A33) : Color(hex: 0xDCE7F8))
            let renderer = ImageRenderer(content: sheet.environment(\.colorScheme, .dark))
            renderer.scale = 2
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            let url = directory.appendingPathComponent("9-pill-states-\(dark ? "dark" : "light").png")
            try png.write(to: url)
            print("wrote \(url.lastPathComponent)")
        }
    }

    /// Renders through a real (off-screen) window so AppKit controls draw too.
    @MainActor
    private static func write<V: View>(_ view: V, size: CGSize, dark: Bool, to url: URL) throws {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        window.displayIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try png.write(to: url)
        print("wrote \(url.lastPathComponent)")
        window.close()
    }

    // MARK: - Sample data

    private static func sampleModel() -> AppModel {
        let settings = Settings.shared
        settings.persistsChanges = false
        settings.cloudCleanup = true
        settings.activationID = "sample-activation"
        settings.licenseKey = "FOX-7Q2D-K9WM-4XRT-8F2K"
        settings.holdRightOption = true
        settings.handsFree = true
        settings.language = "auto"
        settings.launchAtLogin = true
        settings.shareAppName = true
        settings.historyRetention = .days30
        settings.keepAudio = false
        settings.hideDictionaryTip = false
        settings.engine = .mlx

        let calendar = Calendar.current
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 16, hour: 19, minute: 30))!
        settings.activatedAt = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12))!.timeIntervalSince1970

        let library = Library.sample { library in
            library.history = sampleHistory(now: now, calendar: calendar)
            library.dictionary = [
                DictionaryEntry(text: "Khairul Muhtadin", category: .name),
                DictionaryEntry(text: "Jakmall", category: .company),
                DictionaryEntry(text: "Foxtation", category: .product),
                DictionaryEntry(text: "n8n", category: .tool),
                DictionaryEntry(text: "Khaisa Studio", category: .company),
                DictionaryEntry(text: "bagaimana", from: "gimana", scope: .email),
                DictionaryEntry(text: "by the way", from: "btw"),
            ]
            library.snippets = [
                Snippet(cue: "my email", expansion: "[YOUR EMAIL]", used: 48),
                Snippet(cue: "standup", expansion: "Kemarin: … Hari ini: … Blocker: …", used: 31),
                Snippet(cue: "polish prompt", expansion: "Rewrite this to be clearer and shorter. Keep my tone and keep Indonesian words as they are.", used: 22),
                Snippet(cue: "alamat kantor", expansion: "[YOUR OFFICE ADDRESS]", used: 9),
                Snippet(cue: "my calendar", expansion: "[YOUR BOOKING LINK]", used: 4),
            ]
        }

        let model = AppModel(settings: settings, library: library)
        model.snapshotDate = now
        model.snapshotMicrophone = "MacBook Pro Microphone"
        model.snapshotUserName = "Khairul Muhtadin"
        let resets = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 7))!
        model.usage = CloudUsage(used: 186, limit: 500, resets_at: ISO8601DateFormatter().string(from: resets))
        model.license = LicenseInfo(status: "granted", display_key: "****-8F2K", expires_at: nil,
                                    activations: .init(used: 1, limit: 3),
                                    this_device: .init(activation_id: "sample-activation", label: "MacBook Pro", created_at: nil),
                                    portal_url: "https://polar.sh")
        return model
    }

    private static let lines: [(String, String, String)] = [
        ("Slack", "com.tinyspeck.slackmacgap", "Oke, aku cek dulu deploy-nya ya. Kalau aman, kita merge sebelum jam tujuh."),
        ("Mail", "com.apple.mail", "Hi team, here's the summary from today's sync. The new onboarding flow ships next Tuesday."),
        ("Cursor", "com.todesktop.230313mzl4w4u92", "Refactor the upload handler so retries use exponential backoff and log the request ID."),
        ("Notes", "com.apple.Notes", "Ide konten minggu depan: tutorial singkat setup automation n8n untuk tim ops."),
        ("WhatsApp", "net.whatsapp.WhatsApp", "Siap, nanti aku kabari lagi setelah meeting. Thanks ya!"),
        ("Slack", "com.tinyspeck.slackmacgap", "Webhook dari Polar udah masuk, tinggal cek di Cloudflare dashboard."),
        ("Cursor", "com.todesktop.230313mzl4w4u92", "Move the license check into the Cloudflare worker and cache the Polar reply for an hour."),
        ("Telegram", "ru.keepcoder.Telegram", "Nanti malam aku kirim draft-nya ya, sekalian sama invoice dari Polar."),
        ("Notion", "notion.id", "Catatan rapat: migrasi ke Cloudflare selesai minggu ini, lalu kita uji Durable Object."),
        ("Slack", "com.tinyspeck.slackmacgap", "Aku udah push the fix, tinggal review aja and we can ship it."),
        ("Cursor", "com.todesktop.230313mzl4w4u92", "Tolong rename this function jadi fetchUsage, terus update the tests juga."),
    ]

    /// ~150 days of dictations from a fixed pseudo-random sequence, plus the
    /// design's five entries today.
    private static func sampleHistory(now: Date, calendar: Calendar) -> [HistoryEntry] {
        var seed: UInt64 = 42
        func next(_ bound: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int((seed >> 33) % UInt64(bound))
        }
        func entry(_ date: Date, _ line: (String, String, String), cloud: Bool) -> HistoryEntry {
            let words = TextRules.wordCount(line.2)
            return HistoryEntry(date: date, appName: line.0, bundleID: line.1, raw: line.2.lowercased(), final: line.2,
                                words: words, seconds: Double(words) / 142 * 60, cloudUsed: cloud,
                                changes: cloud ? CleanupChanges(fillers_removed: next(3), self_corrections: next(2), formatting_fixes: next(3)) : nil)
        }

        var history: [HistoryEntry] = []
        let today = calendar.startOfDay(for: now)
        for (index, time) in [(18, 42), (17, 15), (16, 3), (14, 28), (11, 50)].enumerated() {
            let date = calendar.date(bySettingHour: time.0, minute: time.1, second: 0, of: today)!
            history.append(entry(date, lines[index], cloud: true))
        }
        for daysAgo in 1...150 {
            let day = calendar.date(byAdding: .day, value: -daysAgo, to: today)!
            // A six-day streak up to today, then a gap, then a looser pattern.
            if daysAgo == 6 || (daysAgo > 6 && next(10) < 3) { continue }
            for _ in 0..<(1 + next(daysAgo < 30 ? 14 : 6)) {
                let date = calendar.date(byAdding: .minute, value: 8 * 60 + next(12 * 60), to: day)!
                history.append(entry(date, lines[next(lines.count)], cloud: next(10) < 8))
            }
        }
        return history.sorted { $0.date > $1.date }
    }
}
