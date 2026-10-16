import AppKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library

    var body: some View {
        let calendar = Calendar.current
        let today = library.history.filter { calendar.isDate($0.date, inSameDayAs: model.now) }
        let todayStats = Stats(today)
        let allStats = Stats(library.history)
        let streak = Stats.streak(Stats.perDay(library.history), today: model.now)

        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(alignment: .bottom, spacing: 24) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(model.greeting).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                            HStack(spacing: 6) {
                                Text(model.triggerVerb)
                                Kbd(text: model.triggerKey)
                                Text(model.triggerVerb == "Hold" ? "anywhere to dictate. Release to paste."
                                                                 : "anywhere to dictate. Press again to paste.")
                            }
                            .font(.system(size: 14))
                            .foregroundStyle(Fx.secondary)
                        }
                        Spacer()
                        Button(action: model.onStartDictation) {
                            Label("Start dictation", systemImage: "mic.fill").font(.system(size: 13.5, weight: .medium))
                        }
                        .buttonStyle(FxButtonStyle(kind: .primary, height: 36))
                    }

                    HStack(spacing: 12) {
                        StatCard(title: "Words today", value: todayStats.words.formatted(), unit: nil)
                        StatCard(title: "Avg. speed", value: "\(allStats.wpm)", unit: "wpm")
                        StatCard(title: "Time saved", value: "\(todayStats.minutesSaved)", unit: "min")
                        StatCard(title: "Streak", value: "\(streak)", unit: streak == 1 ? "day" : "days")
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Eyebrow(text: "Today")
                            Spacer()
                            Button("View all") { model.section = .history }
                                .buttonStyle(.plain)
                                .font(.system(size: 12.5))
                                .foregroundStyle(Fx.accent)
                        }
                        if today.isEmpty {
                            Text("Nothing dictated yet today. \(model.triggerVerb) \(model.triggerKey) in any app and start talking.")
                                .font(.system(size: 13.5))
                                .foregroundStyle(Fx.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .outlined(radius: 10)
                        } else {
                            HistoryList(model: model, library: library, entries: Array(today.prefix(8)))
                        }
                    }
                }
                .padding(32)
            }
        }
    }

    private var header: some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(settings.cloudReady ? Fx.good : Fx.track).frame(width: 8, height: 8)
                Text(settings.cloudReady ? "Cloud cleanup on" : "Cloud cleanup off").foregroundStyle(Fx.ink)
                Text("·").foregroundStyle(Fx.track)
                Text(model.microphoneName).foregroundStyle(Fx.secondary)
            }
            .font(.system(size: 12.5))
            .contentShape(Rectangle())
            .onTapGesture { model.openSettings(.privacy) }
            Spacer()
            HStack(spacing: 4) {
                IconButton(symbol: "magnifyingglass", label: "Search history") { model.section = .history }
                Text(model.initials)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Fx.card)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(Fx.ink))
                    .padding(.leading, 4)
                    .help(model.fullName)
            }
        }
        .padding(.leading, 32)
        .padding(.trailing, 20)
        .frame(height: 52)
        .overlay(alignment: .bottom) { Hairline() }
    }
}

struct StatCard: View {
    var title: String
    var value: String
    var unit: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(value).font(.system(size: 26, weight: .medium)).tracking(-0.5)
                if let unit { Text(unit).font(.system(size: 14)).foregroundStyle(Fx.secondary) }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .outlined(radius: 10)
    }
}

/// Rows of "time · app · text" with replay, copy and delete on hover.
struct HistoryList: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library
    var entries: [HistoryEntry]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(entries) { entry in
                if entry.id != entries.first?.id { Hairline() }
                row(entry)
            }
        }
        .outlined(radius: 10)
    }

    private func row(_ entry: HistoryEntry) -> some View {
        let hovered = model.hoveredRow == entry.id
        return HStack(spacing: 16) {
            Text(AppModel.timeFormatter.string(from: entry.date))
                .font(Fx.mono(12)).foregroundStyle(Fx.secondary)
                .frame(width: 56, alignment: .leading)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 2).fill(Fx.appColor(entry.appName)).frame(width: 6, height: 6)
                Text(entry.appName.isEmpty ? "Unknown" : entry.appName).lineLimit(1)
            }
            .font(.system(size: 12))
            .foregroundStyle(Fx.ink.opacity(0.85))
            .frame(width: 96, alignment: .leading)
            Text(entry.final)
                .font(.system(size: 14))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(entry.cloudUsed && entry.raw != entry.final ? "Heard: \(entry.raw)" : entry.final)
            HStack(spacing: 2) {
                if library.audioURL(entry) != nil {
                    IconButton(symbol: model.playing == entry.id ? "stop.fill" : "play.fill", label: "Play audio") { model.play(entry) }
                }
                IconButton(symbol: "doc.on.doc", label: "Copy text") { model.copy(entry.final) }
                IconButton(symbol: "trash", label: "Delete") { library.delete(entry) }
            }
            .opacity(hovered ? 1 : 0)
        }
        .padding(.leading, 16)
        .padding(.trailing, 12)
        .padding(.vertical, 9)
        .background(hovered ? Fx.wash : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoveredRow = entry.id } else if model.hoveredRow == entry.id { model.hoveredRow = nil }
        }
    }
}

/// Every kept dictation, newest first, grouped by day.
struct HistoryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library

    var body: some View {
        let calendar = Calendar.current
        let days = Dictionary(grouping: library.history) { calendar.startOfDay(for: $0.date) }
        let order = days.keys.sorted(by: >)

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .firstTextBaseline) {
                    Button { model.section = .home } label: {
                        Label("Home", systemImage: "chevron.left").font(.system(size: 13))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Fx.secondary)
                    Spacer()
                }
                HStack(alignment: .firstTextBaseline) {
                    Text("History").font(.system(size: 26, weight: .semibold)).tracking(-0.5)
                    Spacer()
                    Text("\(library.history.count) dictations · \(model.settings.historyRetention == .forever ? "kept forever" : "kept \(model.settings.historyRetention.label.lowercased())")")
                        .font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
                }
                if library.history.isEmpty {
                    Text(model.settings.historyRetention == .off
                         ? "History is off. Turn it on in Settings › Data & Privacy."
                         : "No dictations yet.")
                        .font(.system(size: 13.5)).foregroundStyle(Fx.secondary)
                }
                ForEach(order, id: \.self) { day in
                    VStack(alignment: .leading, spacing: 10) {
                        Eyebrow(text: dayTitle(day))
                        HistoryList(model: model, library: library, entries: days[day] ?? [])
                    }
                }
            }
            .padding(32)
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDate(day, inSameDayAs: model.now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: model.now), calendar.isDate(day, inSameDayAs: yesterday) {
            return "Yesterday"
        }
        return AppModel.dayFormatter.string(from: day)
    }
}
