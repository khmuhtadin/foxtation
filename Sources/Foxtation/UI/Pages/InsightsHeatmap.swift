import SwiftUI

/// GitHub-style grid of the last weeks: one column per week (Monday on top),
/// month labels above, Mon/Wed/Fri on the left, a Less→More legend. Shows as
/// many weeks as fit the width (up to 26), about 20 in a default-size window.
struct InsightsHeatmap: View {
    var counts: [Date: Int]
    var now: Date

    private let cell: CGFloat = 14
    private let gap: CGFloat = 4
    private let labelWidth: CGFloat = 30
    /// Accent opacity for levels 1–4; level 0 is the wash.
    static let levels: [Double] = [0.28, 0.5, 0.75, 1]

    var body: some View {
        GeometryReader { proxy in
            grid(weeks: min(26, max(4, Int((proxy.size.width - labelWidth) / (cell + gap)))))
        }
        .frame(height: 13 + 6 + 7 * cell + 6 * gap + 6 + 12 + cell)
    }

    private func grid(weeks: Int) -> some View {
        let columns = weekStarts(weeks)
        let most = counts.values.max() ?? 0

        return VStack(alignment: .leading, spacing: 6) {
            // Month labels: shown above the first week that starts in that month.
            HStack(spacing: gap) {
                Color.clear.frame(width: labelWidth, height: 1)
                ForEach(columns.indices, id: \.self) { index in
                    Text(monthLabel(columns, index))
                        .font(FXFont.caption)
                        .foregroundStyle(Color.fxSecondary)
                        .fixedSize()
                        .frame(width: cell, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: gap) {
                VStack(alignment: .leading, spacing: gap) {
                    ForEach(0..<7, id: \.self) { row in
                        Text(["Mon", "", "Wed", "", "Fri", "", ""][row])
                            .font(FXFont.caption)
                            .foregroundStyle(Color.fxSecondary)
                            .frame(width: labelWidth, height: cell, alignment: .leading)
                    }
                }
                ForEach(columns, id: \.self) { start in
                    VStack(spacing: gap) {
                        ForEach(0..<7, id: \.self) { row in
                            square(for: Calendar.current.date(byAdding: .day, value: row, to: start)!, most: most)
                        }
                    }
                }
            }
            HStack(spacing: gap) {
                Text("Less").padding(.trailing, 2)
                RoundedRectangle(cornerRadius: 3).fill(Color.fxWash).frame(width: cell, height: cell)
                ForEach(Self.levels, id: \.self) { opacity in
                    RoundedRectangle(cornerRadius: 3).fill(Color.fxAccent.opacity(opacity)).frame(width: cell, height: cell)
                }
                Text("More").padding(.leading, 2)
            }
            .font(FXFont.caption)
            .foregroundStyle(Color.fxSecondary)
            .padding(.top, 12)
        }
    }

    @ViewBuilder
    private func square(for day: Date, most: Int) -> some View {
        if day > now {
            Color.clear.frame(width: cell, height: cell)
        } else {
            let count = counts[day] ?? 0
            RoundedRectangle(cornerRadius: 3)
                .fill(count == 0 ? Color.fxWash : Color.fxAccent.opacity(Self.levels[level(count, most: most) - 1]))
                .frame(width: cell, height: cell)
                .help("\(count) \(count == 1 ? "dictation" : "dictations") · \(Format.day(day))")
        }
    }

    /// 1…4, relative to the busiest day.
    private func level(_ count: Int, most: Int) -> Int {
        min(4, max(1, Int((Double(count) / Double(max(1, most)) * 4).rounded(.up))))
    }

    /// The Monday of each column, oldest first; the last column is this week.
    private func weekStarts(_ weeks: Int) -> [Date] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let sinceMonday = (calendar.component(.weekday, from: today) + 5) % 7  // weekday 1 = Sunday
        let thisMonday = calendar.date(byAdding: .day, value: -sinceMonday, to: today)!
        return (0..<weeks).reversed().map { calendar.date(byAdding: .day, value: -7 * $0, to: thisMonday)! }
    }

    private func monthLabel(_ columns: [Date], _ index: Int) -> String {
        let calendar = Calendar.current
        let month = calendar.component(.month, from: columns[index])
        if index > 0, calendar.component(.month, from: columns[index - 1]) == month { return "" }
        if index == 0 { return "" }  // a partial first month would crowd the next label
        return calendar.shortMonthSymbols[month - 1]
    }
}
