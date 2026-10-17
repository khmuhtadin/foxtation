import SwiftUI

enum InsightsRange: Hashable {
    case days7, days30, all

    var days: Int? {
        switch self {
        case .days7: return 7
        case .days30: return 30
        case .all: return nil
        }
    }
}

struct InsightsPage: View {
    @ObservedObject var model: AppModel
    // Plain `State`: this toolchain has no SwiftUI macro plugin for `@State`.
    private let rangeState = State(initialValue: InsightsRange.days30)
    private var range: InsightsRange { rangeState.wrappedValue }

    var body: some View {
        let now = model.now()
        let all = model.history.entries
        let entries = Stats.lastDays(range.days, of: all, now: now)

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PageHeader(title: "Insights") {
                    PillPicker(selection: rangeState.projectedValue, items: [(.days7, "7 days"), (.days30, "30 days"), (.all, "All time")])
                }
                .padding(.bottom, 8)

                HStack(alignment: .top, spacing: 16) {
                    speedCard(entries)
                    fixesCard(entries)
                    wordsCard(entries)
                }
                .fixedSize(horizontal: false, vertical: true)

                HStack(alignment: .top, spacing: 16) {
                    appsCard(entries)
                        .frame(maxWidth: .infinity)
                    streakCard(all, now: now)
                        .frame(maxWidth: .infinity)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .scrollIndicators(.never)
    }

    // MARK: - Top row

    private func speedCard(_ entries: [Dictation]) -> some View {
        let wpm = Stats.wpm(entries)
        let typing = Int(Stats.typingWPM)
        let top = Double(max(wpm, typing))
        let ratio = Double(wpm) / Stats.typingWPM

        return InsightsCard(title: "Speaking speed") {
            BigNumber(value: wpm > 0 ? "\(wpm)" : "—", unit: wpm > 0 ? "wpm" : nil)
            VStack(spacing: 10) {
                speedBar("You", wpm, fraction: Double(wpm) / top, color: .fxAccent)
                speedBar("Typing", typing, fraction: Double(typing) / top, color: .fxTrack)
            }
            Text(wpm == 0 ? "No dictations in this range yet."
                 : ratio >= 1.05 ? String(format: "%.1f× faster than typing", ratio)
                 : "About as fast as typing")
                .font(FXFont.detail)
                .foregroundStyle(Color.fxSecondary)
        }
    }

    private func speedBar(_ label: String, _ value: Int, fraction: Double, color: Color) -> some View {
        HStack(spacing: 12) {
            Text(label).font(FXFont.detail).foregroundStyle(Color.fxInk).frame(width: 50, alignment: .leading)
            InsightsBar(fraction: fraction, color: color)
            Text("\(value)").font(FXFont.number).foregroundStyle(Color.fxInk).frame(width: 34, alignment: .trailing)
        }
    }

    private func fixesCard(_ entries: [Dictation]) -> some View {
        let fixes = Stats.fixes(entries)
        return InsightsCard(title: "Fixes by Foxtation Cloud") {
            BigNumber(value: Format.number(fixes.total))
            VStack(spacing: 8) {
                InsightsLine(label: "Filler words removed", value: Format.number(fixes.fillersRemoved))
                InsightsLine(label: "Punctuation & casing", value: Format.number(fixes.formattingFixes))
                InsightsLine(label: "Self-corrections", value: Format.number(fixes.selfCorrections))
            }
        }
    }

    private func wordsCard(_ entries: [Dictation]) -> some View {
        InsightsCard(title: "Words dictated") {
            BigNumber(value: Format.number(Stats.words(entries)))
            VStack(spacing: 8) {
                InsightsLine(label: "Typing time saved", value: Format.duration(minutes: Stats.minutesSaved(entries)))
                InsightsLine(label: "Dictations", value: Format.number(entries.count))
                InsightsLine(label: "Mixed ID–EN", value: "\(Int((Stats.mixedShare(entries) * 100).rounded()))%")
            }
        }
    }

    // MARK: - Bottom row

    private func appsCard(_ entries: [Dictation]) -> some View {
        let shares = Stats.byApp(entries)
        let apps = Stats.appCount(entries)
        let top = shares.map(\.share).max() ?? 1

        return FXCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text("By app").font(FXFont.cardTitle).foregroundStyle(Color.fxInk)
                    Spacer()
                    Text("\(apps) \(apps == 1 ? "app" : "apps") used").font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                }
                if shares.isEmpty {
                    Text("Apps you dictate into show up here.")
                        .font(FXFont.detail)
                        .foregroundStyle(Color.fxSecondary)
                } else {
                    VStack(spacing: 14) {
                        ForEach(shares, id: \.self) { share in
                            HStack(spacing: 12) {
                                Text(share.app)
                                    .font(FXFont.body)
                                    .foregroundStyle(share.isOther ? Color.fxSecondary : Color.fxInk)
                                    .lineLimit(1)
                                    .frame(width: 80, alignment: .leading)
                                InsightsBar(fraction: share.share / top, color: share.isOther ? .fxTrack : .fxAccent)
                                Text("\(Int((share.share * 100).rounded()))%")
                                    .font(FXFont.number)
                                    .foregroundStyle(Color.fxInk)
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func streakCard(_ entries: [Dictation], now: Date) -> some View {
        let current = Stats.currentStreak(entries, now: now)
        let longest = Stats.longestStreak(entries)

        return FXCard(padding: 20) {
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    Text(current > 0 ? "\(current)-day streak" : "No streak yet")
                        .font(FXFont.cardTitle)
                        .foregroundStyle(Color.fxInk)
                    Spacer()
                    if longest > 0 {
                        Text("Longest · \(longest) \(longest == 1 ? "day" : "days")")
                            .font(FXFont.detail)
                            .foregroundStyle(Color.fxSecondary)
                    }
                }
                InsightsHeatmap(counts: Stats.dayCounts(entries), now: Calendar.current.startOfDay(for: now))
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

// MARK: - Pieces

/// A top-row card: small title over a big number, then details.
struct InsightsCard<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        FXCard(padding: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                VStack(alignment: .leading, spacing: 16) { content }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }
}

/// "Dictations ........ 1,146"
struct InsightsLine: View {
    var label: String
    var value: String

    var body: some View {
        HStack {
            Text(label).font(FXFont.detail).foregroundStyle(Color.fxInk)
            Spacer()
            Text(value).font(FXFont.number).foregroundStyle(Color.fxInk)
        }
    }
}

/// A thick capsule bar with no track, as in the By app and speed cards.
struct InsightsBar: View {
    var fraction: Double
    var color: Color

    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(color).frame(width: fraction > 0 ? max(6, proxy.size.width * min(1, fraction)) : 0)
        }
        .frame(height: 7)
    }
}
