import SwiftUI

/// Words Foxtation must spell exactly, and replacements applied after cleanup.
struct DictionaryPage: View {
    @ObservedObject var model: AppModel

    @AppStorage("dictionaryIntroHidden") private var introHidden = false
    @StateObject private var state = DictionaryPageState()

    private var library: Library { model.library }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Dictionary") {
                    Button { state.editing = .new } label: {
                        Label("Add word", systemImage: "plus")
                    }
                    .fxButton(.dark)
                }
                .padding(.bottom, 22)

                if !introHidden {
                    intro.padding(.bottom, 22)
                }

                tabsRow
                rows
                note.padding(.top, 14)
            }
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .sheet(item: $state.editing) { target in
            DictionaryEditor(library: library, target: target) { state.editing = nil }
        }
    }

    // MARK: - Intro

    private var intro: some View {
        let suggestions = library.suggestions(from: model.history.entries)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text("Foxtation spells it your way.")
                    .font(FXFont.headline)
                    .foregroundStyle(Color.fxInk)
                Spacer()
                IconButton(symbol: "xmark", label: "Hide this tip", size: 10) { introHidden = true }
                    .padding(.top, -6)
                    .padding(.trailing, -8)
                    .padding(.bottom, -6)
            }
            Text("Add names, product terms and slang once. Every dictation and cloud cleanup uses this list, so “Jakmall” never turns into “jack mall”.")
                .font(FXFont.body)
                .foregroundStyle(Color.fxSecondary)
                .lineSpacing(3)
                .frame(maxWidth: 520, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            if !suggestions.isEmpty {
                HStack(spacing: 8) {
                    Text("Suggested from your history")
                        .font(FXFont.detail)
                        .foregroundStyle(Color.fxSecondary)
                        .padding(.trailing, 2)
                    ForEach(suggestions, id: \.self) { word in
                        Button { library.terms.append(Term(text: word, category: .other)) } label: {
                            Text("+ \(word)")
                                .font(FXFont.detail.weight(.medium))
                                .foregroundStyle(Color.fxInk)
                                .padding(.horizontal, 10)
                                .frame(height: 26)
                                .background(Capsule().fill(Color.fxCard))
                                .overlay(Capsule().strokeBorder(Color.fxSeparator))
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Add “\(word)” to your dictionary")
                    }
                }
                .padding(.top, 8)
            }
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxWash))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.fxSeparator))
    }

    // MARK: - Tabs and search

    private var tabsRow: some View {
        let words = library.terms.count
        let replacements = library.replacements.count
        return HStack(alignment: .bottom) {
            UnderlineTabs(selection: $state.tab, items: [
                (.all, "All \(words + replacements)"),
                (.words, "Words \(words)"),
                (.replacements, "Replacements \(replacements)"),
            ])
            Spacer()
            SearchField(placeholder: "Search", text: $state.search, width: 200)
                .padding(.bottom, 6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.fxSeparator).frame(height: 1).offset(y: 0.5) }
    }

    // MARK: - Rows

    private var query: String { state.search.trimmingCharacters(in: .whitespaces).lowercased() }

    private var shownTerms: [Term] {
        guard state.tab != .replacements else { return [] }
        return library.terms.filter { query.isEmpty || $0.text.lowercased().contains(query) }
    }

    private var shownReplacements: [Replacement] {
        guard state.tab != .words else { return [] }
        return library.replacements.filter {
            query.isEmpty || $0.from.lowercased().contains(query) || $0.to.lowercased().contains(query)
        }
    }

    @ViewBuilder private var rows: some View {
        let terms = shownTerms
        let replacements = shownReplacements
        if terms.isEmpty && replacements.isEmpty {
            emptyState
        } else {
            VStack(spacing: 0) {
                ForEach(terms) { term in
                    row(id: term.id, open: { state.editing = .term(term) },
                        delete: { library.terms.removeAll { $0.id == term.id } }) {
                        Text(term.text).foregroundStyle(Color.fxInk)
                    } trailing: {
                        term.category.label
                    }
                    RowDivider()
                }
                ForEach(replacements) { replacement in
                    row(id: replacement.id, open: { state.editing = .replacement(replacement) },
                        delete: { library.replacements.removeAll { $0.id == replacement.id } }) {
                        HStack(spacing: 10) {
                            Text(replacement.from).foregroundStyle(Color.fxSecondary)
                            Image(systemName: "arrow.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(Color.fxAccent)
                            Text(replacement.to).foregroundStyle(Color.fxInk)
                        }
                    } trailing: {
                        "Replace · \(replacement.scopeLabel)"
                    }
                    RowDivider()
                }
            }
        }
    }

    private func row<Leading: View>(id: UUID, open: @escaping () -> Void, delete: @escaping () -> Void,
                                    @ViewBuilder leading: () -> Leading, trailing: () -> String) -> some View {
        Button(action: open) {
            HStack(spacing: 12) {
                leading()
                    .font(FXFont.body)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text(trailing())
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxSecondary)
                    .lineLimit(1)
                    .frame(width: 190, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 6).fill(state.hovered == id ? Color.fxWash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { state.hovered = id } else if state.hovered == id { state.hovered = nil }
        }
        .contextMenu {
            Button("Edit…", action: open)
            Button("Delete", role: .destructive, action: delete)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            if !query.isEmpty {
                Text("Nothing matches “\(state.search.trimmingCharacters(in: .whitespaces))”.")
                    .font(FXFont.body)
                    .foregroundStyle(Color.fxSecondary)
            } else {
                Text(state.tab == .replacements ? "No replacements yet" : "Your dictionary is empty")
                    .font(FXFont.cardTitle)
                    .foregroundStyle(Color.fxInk)
                Text(state.tab == .replacements
                     ? "Swap a word you say for the one you want, like “btw” → “by the way”."
                     : "Add the names and terms Foxtation should always spell your way.")
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxSecondary)
                Button(state.tab == .replacements ? "Add replacement" : "Add word") {
                    state.editing = state.tab == .replacements ? .newReplacement : .new
                }
                .fxButton(.secondary, compact: true)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private var note: some View {
        Text("Foxtation Cloud gets the first \(CloudCleanup.maxVocabulary) words as vocabulary. Replacements run on this Mac.")
            .font(FXFont.caption)
            .foregroundStyle(Color.fxSecondary)
            .padding(.horizontal, 8)
    }
}

enum DictionaryTab: Hashable { case all, words, replacements }

/// The page's own view state (SwiftUI's @State needs macros, which this build can't use).
final class DictionaryPageState: ObservableObject {
    @Published var tab: DictionaryTab = .all
    @Published var search = ""
    @Published var editing: DictionaryEditTarget?
    @Published var hovered: UUID?
}

/// What the editor sheet opens on.
enum DictionaryEditTarget: Identifiable {
    case new, newReplacement, term(Term), replacement(Replacement)

    var id: String {
        switch self {
        case .new: return "new"
        case .newReplacement: return "new-replacement"
        case .term(let term): return term.id.uuidString
        case .replacement(let replacement): return replacement.id.uuidString
        }
    }
}
