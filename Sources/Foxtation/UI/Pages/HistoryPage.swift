import SwiftUI

/// Every kept dictation, grouped by day, with search. Reached from Home's "View all".
struct HistoryPage: View {
    @ObservedObject var model: AppModel
    // Plain `State`: this toolchain has no SwiftUI macro plugin for `@State`.
    private let queryState = State(initialValue: "")
    private var query: String { queryState.wrappedValue }

    var body: some View {
        let entries = model.history.entries
        let groups = Self.groups(filtered(entries))

        VStack(alignment: .leading, spacing: 0) {
            TextLink(title: "Home", symbol: "chevron.left") { model.page = .home }
                .padding(.top, -8)
                .padding(.bottom, 2)

            PageHeader(title: "History",
                       subtitle: entries.isEmpty ? nil : "\(Format.number(entries.count)) \(entries.count == 1 ? "dictation" : "dictations")") {
                SearchField(placeholder: "Search history", text: queryState.projectedValue, width: 240)
            }
            .padding(.bottom, 22)

            if entries.isEmpty {
                HistoryEmptyCard(symbol: "waveform",
                                 title: "No dictations yet",
                                 detail: "Dictate anywhere with \(model.triggerKey). Everything stays on this Mac.")
                Spacer()
            } else if groups.isEmpty {
                HistoryEmptyCard(symbol: "magnifyingglass",
                                 title: "No matches",
                                 detail: "Nothing in your history contains “\(query)”.")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups, id: \.day) { group in
                            SectionLabel(text: dayTitle(group.day))
                                .padding(.top, group.day == groups.first?.day ? 0 : 14)
                            HistoryRowsCard(model: model, dictations: group.items)
                        }
                    }
                }
                .scrollIndicators(.never)
            }
        }
    }

    private func filtered(_ entries: [Dictation]) -> [Dictation] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter {
            $0.text.localizedCaseInsensitiveContains(needle)
                || $0.raw.localizedCaseInsensitiveContains(needle)
                || $0.app.localizedCaseInsensitiveContains(needle)
        }
    }

    /// Newest day first; entries keep their newest-first order.
    static func groups(_ entries: [Dictation]) -> [(day: Date, items: [Dictation])] {
        var result: [(day: Date, items: [Dictation])] = []
        for dictation in entries {
            let day = Calendar.current.startOfDay(for: dictation.date)
            if result.last?.day == day {
                result[result.count - 1].items.append(dictation)
            } else {
                result.append((day, [dictation]))
            }
        }
        return result
    }

    /// "Today", "Yesterday" or "12 Oct 2026".
    private func dayTitle(_ day: Date) -> String {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: model.now())
        if day == today { return "Today" }
        if day == calendar.date(byAdding: .day, value: -1, to: today) { return "Yesterday" }
        return Format.day(day)
    }
}
