import SwiftUI

/// Centered column used by Dictionary, Snippets and Style.
struct PageColumn<Content: View>: View {
    var spacing: CGFloat = 24
    @ViewBuilder var content: () -> Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: spacing) { content() }
                .padding(.horizontal, 40)
                .padding(.vertical, 32)
                .frame(maxWidth: 880)
                .frame(maxWidth: .infinity)
        }
    }
}

struct PageTitle<Trailing: View>: View {
    var title: String
    @ViewBuilder var trailing: () -> Trailing
    var body: some View {
        HStack {
            Text(title).font(.system(size: 26, weight: .semibold)).tracking(-0.5)
            Spacer()
            trailing()
        }
    }
}

struct DictionaryView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var settings: Settings
    @ObservedObject var library: Library

    var body: some View {
        let all = library.dictionary
        let words = all.filter { !$0.isReplacement }
        let replacements = all.filter(\.isReplacement)
        let suggestions = TextRules.suggestions(history: library.history, dictionary: all)
        let shown = filtered(all)

        PageColumn(spacing: 22) {
            PageTitle(title: "Dictionary") {
                Button { add(nil) } label: { Label("Add word", systemImage: "plus") }
                    .buttonStyle(FxButtonStyle(kind: .dark, height: 36))
            }

            if !settings.hideDictionaryTip {
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Foxtation spells it your way.").font(.system(size: 18, weight: .semibold))
                            Text("Add names, product terms and slang once. Every dictation and cloud cleanup uses this list, so “Jakmall” never turns into “jack mall”.")
                                .font(.system(size: 13.5))
                                .lineSpacing(3)
                                .foregroundStyle(Fx.ink.opacity(0.85))
                                .frame(maxWidth: 560, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        IconButton(symbol: "xmark", label: "Dismiss") { settings.hideDictionaryTip = true }
                    }
                    if !suggestions.isEmpty { suggestionRow(suggestions) }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .background(RoundedRectangle(cornerRadius: 12).fill(Fx.accent.opacity(0.07)))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Fx.accent.opacity(0.2), lineWidth: 1))
            } else if !suggestions.isEmpty {
                suggestionRow(suggestions)
            }

            VStack(spacing: 0) {
                UnderlineTabs(options: [(DictionaryFilter.all, "All", "\(all.count)"),
                                        (.words, "Words", "\(words.count)"),
                                        (.replacements, "Replacements", "\(replacements.count)")],
                              selection: $model.dictionaryFilter) {
                    SearchField(text: $model.dictionarySearch)
                }
                if shown.isEmpty {
                    Text(all.isEmpty ? "Nothing here yet. Add a name, a product or a word Foxtation keeps getting wrong."
                                     : "No matches.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Fx.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 8)
                }
                ForEach(shown) { entry in
                    row(entry)
                    if entry.id != shown.last?.id { Hairline() }
                }
            }
        }
    }

    private func filtered(_ all: [DictionaryEntry]) -> [DictionaryEntry] {
        let query = model.dictionarySearch.trimmingCharacters(in: .whitespaces).lowercased()
        return all.filter { entry in
            switch model.dictionaryFilter {
            case .all: break
            case .words: if entry.isReplacement { return false }
            case .replacements: if !entry.isReplacement { return false }
            }
            return query.isEmpty || entry.text.lowercased().contains(query) || entry.from.lowercased().contains(query)
        }
    }

    private func suggestionRow(_ suggestions: [String]) -> some View {
        FlowLayout(spacing: 8) {
            Text("Suggested from your history").font(.system(size: 12.5)).foregroundStyle(Fx.secondary)
                .frame(height: 30)
            ForEach(suggestions, id: \.self) { word in
                Button {
                    library.dictionary.append(DictionaryEntry(text: word))
                    library.saveDictionary()
                } label: {
                    Text("+ \(word)").font(.system(size: 12.5, weight: .medium))
                        .fixedSize()
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(Capsule().fill(Fx.card))
                        .overlay(Capsule().strokeBorder(Fx.accent.opacity(0.3), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func row(_ entry: DictionaryEntry) -> some View {
        let hovered = model.hoveredRow == entry.id
        return HStack(spacing: 16) {
            Group {
                if entry.isReplacement {
                    HStack(spacing: 10) {
                        Text(entry.from).foregroundStyle(Fx.secondary)
                        Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(Fx.secondary)
                        Text(entry.text)
                    }
                } else {
                    Text(entry.text)
                }
            }
            .font(.system(size: 14))
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(entry.isReplacement ? "Replace · \(entry.scope.map { "\($0.label) only" } ?? "All apps")" : entry.category.label)
                .font(.system(size: 12))
                .foregroundStyle(Fx.secondary)
                .frame(width: 150, alignment: .leading)
            HStack(spacing: 0) {
                IconButton(symbol: "pencil", label: "Edit") { add(entry) }
                IconButton(symbol: "trash", label: "Delete") {
                    library.dictionary.removeAll { $0.id == entry.id }
                    library.saveDictionary()
                }
            }
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 46)
        .background(hovered ? Fx.wash : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoveredRow = entry.id } else if model.hoveredRow == entry.id { model.hoveredRow = nil }
        }
    }

    private func add(_ existing: DictionaryEntry?) {
        guard let entry = Editors.dictionaryEntry(existing) else { return }
        if let index = library.dictionary.firstIndex(where: { $0.id == entry.id }) {
            library.dictionary[index] = entry
        } else {
            library.dictionary.append(entry)
        }
        library.saveDictionary()
    }
}

struct SearchField: View {
    @Binding var text: String
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(Fx.secondary)
            TextField("Search", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .frame(width: 140)
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .outlined(radius: 8)
    }
}

/// Lays children out left to right, wrapping onto new lines.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += line + spacing
                line = 0
            }
            x += size.width + spacing
            line = max(line, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += line + spacing
                line = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            line = max(line, size.height)
        }
    }
}
