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
            Button { model.page = .home } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold))
                    Text("Home")
                }
                .font(FXFont.detail.weight(.medium))
                .foregroundStyle(Color.fxAccent)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.bottom, 10)

            PageHeader(title: "History",
                       subtitle: entries.isEmpty ? nil : "\(Format.number(entries.count)) \(entries.count == 1 ? "dictation" : "dictations")") {
                searchField
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

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.fxSecondary)
            TextField("Search history", text: queryState.projectedValue)
                .textFieldStyle(.plain)
                .font(FXFont.body)
            if !query.isEmpty {
                Button { queryState.wrappedValue = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Color.fxSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .frame(width: 240)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.fxSeparator))
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
