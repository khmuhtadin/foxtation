import SwiftUI

/// Saved text that's pasted in place of a spoken cue.
struct SnippetsPage: View {
    @ObservedObject var model: AppModel

    @StateObject private var state = SnippetsPageState()

    private var library: Library { model.library }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Snippets") {
                    Button { state.editing = .new } label: {
                        Label("New snippet", systemImage: "plus")
                    }
                    .fxButton(.dark)
                }
                .padding(.bottom, 22)

                hero.padding(.bottom, 14)

                if library.snippets.isEmpty {
                    emptyState
                } else {
                    table
                }

                Text("Foxtation Cloud gets the first \(CloudCleanup.maxSnippetCues) cues so cleanup leaves them as you said them.")
                    .font(FXFont.caption)
                    .foregroundStyle(Color.fxSecondary)
                    .padding(.horizontal, 8)
                    .padding(.top, 14)
            }
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
        .sheet(item: $state.editing) { target in
            SnippetsEditor(library: library, target: target) { state.editing = nil }
        }
    }

    // MARK: - Hero

    /// The first two snippets, or the design's examples until there are two.
    private var examples: [(String, String)] {
        if library.snippets.count >= 2 {
            return library.snippets.prefix(2).map { ($0.cue, $0.text) }
        }
        return [("alamat kantor", "[YOUR OFFICE ADDRESS]"), ("standup", "Kemarin: … Hari ini: … Blocker: …")]
    }

    private var hero: some View {
        HStack(alignment: .center, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Say a cue. Drop the whole text.")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.fxCard)
                Text("Save anything you type often — an address, a standup template, a prompt. Speak its cue mid-sentence and Foxtation pastes it in.")
                    .font(FXFont.body)
                    .foregroundStyle(Color.fxCard.opacity(0.78))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 320, alignment: .leading)

            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(examples.indices, id: \.self) { index in
                    let (cue, text) = examples[index]
                    HStack(spacing: 10) {
                        Text("“\(cue)”")
                            .font(FXFont.detail.italic())
                            .foregroundStyle(Color.fxCard)
                            .lineLimit(1)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 6).fill(Color.fxCard.opacity(0.16)))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.fxAccent)
                        Text(SnippetsFormat.oneLine(text))
                            .font(FXFont.detail)
                            .foregroundStyle(Color.fxCard)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 9)
                            .padding(.vertical, 6)
                            .frame(maxWidth: 190, alignment: .leading)
                            .fixedSize(horizontal: true, vertical: false)
                            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.fxCard.opacity(0.28)))
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxInk))
    }

    // MARK: - Table

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                SectionLabel(text: "Cue").frame(width: 170, alignment: .leading)
                SectionLabel(text: "Expands to")
                Spacer()
                SectionLabel(text: "Used").frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 36)
            RowDivider()

            ForEach(library.snippets) { snippet in
                row(snippet)
                RowDivider()
            }
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        Button { state.editing = .snippet(snippet) } label: {
            HStack(spacing: 12) {
                Text(snippet.cue)
                    .font(FXFont.body.weight(.semibold))
                    .foregroundStyle(Color.fxInk)
                    .lineLimit(1)
                    .frame(width: 170, alignment: .leading)
                Text(SnippetsFormat.oneLine(snippet.text))
                    .font(FXFont.body)
                    .foregroundStyle(Color.fxInk.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 12)
                Text("\(Format.number(snippet.used))×")
                    .font(FXFont.caption)
                    .foregroundStyle(Color.fxSecondary)
                    .monospacedDigit()
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.horizontal, 8)
            .frame(height: 51)
            .background(RoundedRectangle(cornerRadius: 6).fill(state.hovered == snippet.id ? Color.fxWash : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            if inside { state.hovered = snippet.id } else if state.hovered == snippet.id { state.hovered = nil }
        }
        .contextMenu {
            Button("Edit…") { state.editing = .snippet(snippet) }
            Button("Delete", role: .destructive) { library.snippets.removeAll { $0.id == snippet.id } }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No snippets yet").font(FXFont.cardTitle).foregroundStyle(Color.fxInk)
            Text("Save an address, a template or a prompt, then say its cue while dictating.")
                .font(FXFont.detail)
                .foregroundStyle(Color.fxSecondary)
            Button("New snippet") { state.editing = .new }
                .fxButton(.secondary, compact: true)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 56)
    }
}

enum SnippetsFormat {
    /// Newlines become spaces, for one-line previews.
    static func oneLine(_ text: String) -> String {
        text.split(whereSeparator: \.isNewline).joined(separator: " ")
    }
}

enum SnippetsEditTarget: Identifiable {
    case new, snippet(Snippet)

    var id: String {
        switch self {
        case .new: return "new"
        case .snippet(let snippet): return snippet.id.uuidString
        }
    }
}

/// Add or edit a snippet: a one-line cue and the text it expands to.
struct SnippetsEditor: View {
    let library: Library
    let target: SnippetsEditTarget
    var close: () -> Void

    @StateObject private var draft: SnippetsDraft

    init(library: Library, target: SnippetsEditTarget, close: @escaping () -> Void) {
        self.library = library
        self.target = target
        self.close = close
        _draft = StateObject(wrappedValue: SnippetsDraft(target: target))
    }

    private var existing: Snippet? {
        if case .snippet(let snippet) = target { return snippet }
        return nil
    }

    private var otherCues: [String] { library.snippets.filter { $0.id != existing?.id }.map(\.cue) }

    private var canSave: Bool {
        DictionaryRules.isValid(draft.cue, others: otherCues)
            && !draft.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        let cueError = DictionaryRules.problem(draft.cue, others: otherCues)
        VStack(alignment: .leading, spacing: 18) {
            Text(existing == nil ? "New snippet" : "Edit snippet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.fxInk)

            DictionaryField(label: "Cue", error: cueError) {
                DictionaryTextField(placeholder: "e.g. alamat kantor", text: $draft.cue, invalid: cueError != nil)
            }

            DictionaryField(label: "Expands to") {
                TextEditor(text: $draft.text)
                    // ⌘↩ saves from inside the box; the Save button's shortcut doesn't reach it.
                    .onKeyPress(.return, phases: .down) { press in
                        guard press.modifiers.contains(.command) else { return .ignored }
                        save()
                        return .handled
                    }
                    .font(FXFont.body)
                    .foregroundStyle(Color.fxInk)
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 140)
                    .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.fxSeparator))
            }

            Text("Say the cue mid-sentence and Foxtation pastes this text in its place.")
                .font(FXFont.caption).foregroundStyle(Color.fxSecondary)

            DictionarySheetButtons(canSave: canSave,
                                   saveWithCommand: true,
                                   onDelete: existing == nil ? nil : { delete() },
                                   onCancel: close,
                                   onSave: { save() })
                .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 460)
        .background(Color.fxCard)
    }

    private func save() {
        guard canSave else { return }
        let cleanCue = DictionaryRules.clean(draft.cue)
        if let existing, let index = library.snippets.firstIndex(where: { $0.id == existing.id }) {
            library.snippets[index].cue = cleanCue
            library.snippets[index].text = draft.text
        } else {
            library.snippets.append(Snippet(cue: cleanCue, text: draft.text))
        }
        close()
    }

    private func delete() {
        if let existing { library.snippets.removeAll { $0.id == existing.id } }
        close()
    }
}

final class SnippetsPageState: ObservableObject {
    @Published var editing: SnippetsEditTarget?
    @Published var hovered: UUID?
}

/// The editor's fields while the sheet is open.
final class SnippetsDraft: ObservableObject {
    @Published var cue = ""
    @Published var text = ""

    init(target: SnippetsEditTarget) {
        if case .snippet(let snippet) = target {
            cue = snippet.cue
            text = snippet.text
        }
    }
}
