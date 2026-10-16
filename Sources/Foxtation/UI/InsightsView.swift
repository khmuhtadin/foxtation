import SwiftUI

struct InsightsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library

    var body: some View {
        let entries = inRange(library.history)
        let stats = Stats(entries)
        let days = Stats.perDay(library.history)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    Text("Insights").font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                    Spacer()
                    Segments(options: [(InsightsRange.days7, "7 days"), (.days30, "30 days"), (.all, "All time")],
                             selection: $model.insightsRange)
                }

                HStack(alignment: .top, spacing: 16) {
                    speedCard(stats)
                    BigNumberCard(title: "Fixes by Foxtation Cloud", value: stats.fixes.formatted(), rows: [
                        ("Filler words removed", stats.fillers.formatted()),
                        ("Punctuation & casing", stats.formatting.formatted()),
                        ("Self-corrections", stats.corrections.formatted()),
                    ])
                    BigNumberCard(title: "Words dictated", value: stats.words.formatted(), rows: [
                        ("Typing time saved", Stats.hoursAndMinutes(stats.minutesSaved)),
                        ("Dictations", stats.dictations.formatted()),
                        ("Mixed ID–EN", "\(stats.mixedPercent)%"),
                    ])
                }
                .fixedSize(horizontal: false, vertical: true)

                GeometryReader { proxy in
                    let left = (proxy.size.width - 16) / 2.25
                    let right = proxy.size.width - 16 - left
                    // As many weeks as fit beside the weekday labels.
                    let weeks = min(26, max(8, Int((right - 40 - 34 + Heatmap.gap) / (Heatmap.cell + Heatmap.gap))))
                    HStack(alignment: .top, spacing: 16) {
                        byAppCard(entries).frame(width: left)
                        streakCard(days, weeks: weeks)
                    }
                }
                .frame(minHeight: 264)
            }
            .padding(32)
        }
    }

    private func inRange(_ history: [HistoryEntry]) -> [HistoryEntry] {
        let days: Double
        switch model.insightsRange {
        case .days7: days = 7
        case .days30: days = 30
        case .all: return history
        }
        let cutoff = model.now.addingTimeInterval(-days * 86_400)
        return history.filter { $0.date >= cutoff }
    }

    private func speedCard(_ stats: Stats) -> some View {
        let wpm = stats.wpm
        let top = Double(max(wpm, Int(Stats.typingWPM)))
        return VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Speaking speed").font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(wpm)").font(.system(size: 34, weight: .medium)).tracking(-1)
                    Text("wpm").font(.system(size: 15)).foregroundStyle(Fx.secondary)
                }
            }
            VStack(spacing: 8) {
                speedBar("You", value: wpm, fraction: Double(wpm) / top, color: Fx.accent)
                speedBar("Typing", value: Int(Stats.typingWPM), fraction: Stats.typingWPM / top, color: Fx.track)
            }
            Text(wpm > 0 ? String(format: "%.1f× faster than typing", Double(wpm) / Stats.typingWPM) : "Dictate a few times to see your speed.")
                .font(.system(size: 12.5)).foregroundStyle(Fx.ink.opacity(0.85))
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .outlined()
    }

    private func speedBar(_ title: String, value: Int, fraction: Double, color: Color) -> some View {
        HStack(spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(Fx.secondary).frame(width: 64, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(color).frame(width: max(8, proxy.size.width * fraction), height: 8)
                    .frame(maxHeight: .infinity)
            }
            .frame(height: 8)
            Text("\(value)").font(Fx.mono(12)).frame(width: 28, alignment: .trailing)
        }
    }

    private func byAppCard(_ entries: [HistoryEntry]) -> some View {
        let (rows, apps) = Stats.byApp(entries)
        let top = rows.map(\.share).max() ?? 1
        return VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                Text("By app").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(apps) \(apps == 1 ? "app" : "apps") used").font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
            }
            if rows.isEmpty {
                Text("No dictations in this range.").font(.system(size: 13)).foregroundStyle(Fx.secondary)
            }
            VStack(spacing: 14) {
                ForEach(rows, id: \.name) { row in
                    let other = row.name == "Other"
                    HStack(spacing: 12) {
                        Text(row.name).font(.system(size: 13)).foregroundStyle(other ? Fx.secondary : Fx.ink)
                            .lineLimit(1).frame(width: 84, alignment: .leading)
                        GeometryReader { proxy in
                            Capsule().fill(other ? Fx.track : Fx.accent)
                                .frame(width: max(6, proxy.size.width * row.share / top), height: 10)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(height: 10)
                        Text("\(Int((row.share * 100).rounded()))%").font(Fx.mono(12)).frame(width: 40, alignment: .trailing)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxHeight: .infinity, alignment: .top)
        .outlined()
    }

    private func streakCard(_ days: [Date: Int], weeks: Int) -> some View {
        let streak = Stats.streak(days, today: model.now)
        return VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("\(streak)-day streak").font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("Longest · \(Stats.longestStreak(days)) days").font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
            }
            Heatmap(days: days, today: model.now, weeks: weeks)
            HStack(spacing: 6) {
                Text("Less")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3).fill(Heatmap.color(level)).frame(width: 12, height: 12)
                }
                Text("More")
            }
            .font(.system(size: 11.5))
            .foregroundStyle(Fx.secondary)
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .outlined()
    }
}

struct BigNumberCard: View {
    var title: String
    var value: String
    var rows: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
                Text(value).font(.system(size: 34, weight: .medium)).tracking(-1)
            }
            VStack(spacing: 6) {
                ForEach(rows, id: \.0) { label, number in
                    HStack {
                        Text(label).foregroundStyle(Fx.ink.opacity(0.85))
                        Spacer()
                        Text(number).font(Fx.mono(12.5))
                    }
                    .font(.system(size: 12.5))
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .outlined()
    }
}

/// Contribution grid: one column per week (Monday first), ending this week.
struct Heatmap: View {
    var days: [Date: Int]
    var today: Date
    var weeks = 20

    static let cell: CGFloat = 14
    static let gap: CGFloat = 4

    /// Columns where a new month begins, skipping any too close to the previous label.
    static func monthStarts(start: Date, weeks: Int, calendar: Calendar) -> [Int] {
        var columns: [Int] = []
        for column in 0..<weeks {
            let monday = calendar.date(byAdding: .weekOfYear, value: column, to: start)!
            let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: monday)!
            let newMonth = calendar.component(.month, from: monday) != calendar.component(.month, from: previous)
            if newMonth, column - (columns.last ?? -3) >= 3 { columns.append(column) }
        }
        return columns
    }

    static func color(_ level: Int) -> Color {
        level == 0 ? Fx.wash : Fx.accent.opacity([0, 0.3, 0.55, 0.8, 1][level])
    }

    var body: some View {
        var calendar = Calendar(identifier: .gregorian)
        calendar.firstWeekday = 2
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: today)!.start
        let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)!
        let top = max(1, days.values.max() ?? 1)
        let step = Self.cell + Self.gap

        return HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: Self.gap) {
                ForEach(0..<7) { row in
                    Text(["Mon", "", "Wed", "", "Fri", "", ""][row]).frame(height: Self.cell)
                }
            }
            .font(.system(size: 10.5))
            .foregroundStyle(Fx.secondary)
            .padding(.top, 18)

            VStack(alignment: .leading, spacing: Self.gap) {
                ZStack(alignment: .topLeading) {
                    ForEach(Self.monthStarts(start: start, weeks: weeks, calendar: calendar), id: \.self) { column in
                        let monday = calendar.date(byAdding: .weekOfYear, value: column, to: start)!
                        Text(monday.formatted(.dateTime.month(.abbreviated)))
                            .fixedSize()
                            .offset(x: CGFloat(column) * step)
                    }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(Fx.secondary)
                .frame(width: CGFloat(weeks) * step - Self.gap, height: 14, alignment: .topLeading)

                HStack(spacing: Self.gap) {
                    ForEach(0..<weeks, id: \.self) { column in
                        VStack(spacing: Self.gap) {
                            ForEach(0..<7) { row in
                                let day = calendar.date(byAdding: .day, value: column * 7 + row, to: start)!
                                let count = days[Calendar.current.startOfDay(for: day)] ?? 0
                                let level = count == 0 ? 0 : min(4, 1 + Int(Double(count - 1) / Double(top) * 4))
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(day > today ? Color.clear : Self.color(level))
                                    .frame(width: Self.cell, height: Self.cell)
                                    .help(count > 0 ? "\(count) dictations · \(AppModel.dayFormatter.string(from: day))" : "")
                            }
                        }
                    }
                }
            }
        }
    }
}
