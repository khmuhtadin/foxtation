import SwiftUI

/// Rules for dictionary words, replacement phrases and snippet cues. They
/// match what Foxtation Cloud accepts (see `CloudCleanup.terms`).
enum DictionaryRules {
    /// nil when `value` is fine. Empty values have no message; callers just
    /// keep Save disabled.
    static func problem(_ value: String, others: [String]) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return nil }
        if trimmed.contains(where: \.isNewline) { return "Keep it on one line." }
        if trimmed.count > CloudCleanup.maxTermLength {
            return "Keep it to \(CloudCleanup.maxTermLength) characters (\(trimmed.count) now)."
        }
        if others.contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == trimmed.lowercased() }) {
            return "“\(trimmed)” is already in your list."
        }
        return nil
    }

    static func isValid(_ value: String, others: [String]) -> Bool {
        !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && problem(value, others: others) == nil
    }

    static func clean(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// A labelled field for the editor sheets, with an inline error under it.
struct DictionaryField<Content: View>: View {
    var label: String
    var error: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(FXFont.detail.weight(.medium)).foregroundStyle(Color.fxSecondary)
            content
            if let error {
                Text(error).font(FXFont.caption).foregroundStyle(Color.fxBad)
            }
        }
    }
}

/// A plain text field in the window's inset style.
struct DictionaryTextField: View {
    var placeholder: String
    @Binding var text: String
    var invalid = false

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(FXFont.body)
            .foregroundStyle(Color.fxInk)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(invalid ? Color.fxBad : Color.fxSeparator))
    }
}

/// The sheet's bottom row: Delete on the left, Cancel and Save on the right.
struct DictionarySheetButtons: View {
    var canSave: Bool
    /// ⌘↩ instead of ↩, for sheets with a multi-line text box.
    var saveWithCommand = false
    var onDelete: (() -> Void)?
    var onCancel: () -> Void
    var onSave: () -> Void

    var body: some View {
        HStack {
            if let onDelete {
                Button("Delete", action: onDelete).fxButton(.destructive)
            }
            Spacer()
            Button("Cancel", action: onCancel)
                .fxButton(.secondary)
                .keyboardShortcut(.cancelAction)
            Button("Save", action: onSave)
                .fxButton(.dark)
                .keyboardShortcut(.return, modifiers: saveWithCommand ? .command : [])
                .disabled(!canSave)
                .opacity(canSave ? 1 : 0.4)
        }
    }
}

/// Add or edit a dictionary word or a replacement.
struct DictionaryEditor: View {
    let library: Library
    let target: DictionaryEditTarget
    var close: () -> Void

    @StateObject private var draft: DictionaryDraft

    init(library: Library, target: DictionaryEditTarget, close: @escaping () -> Void) {
        self.library = library
        self.target = target
        self.close = close
        _draft = StateObject(wrappedValue: DictionaryDraft(target: target))
    }

    private var isNew: Bool {
        switch target {
        case .new, .newReplacement: return true
        case .term, .replacement: return false
        }
    }

    private var editingID: UUID? {
        switch target {
        case .term(let term): return term.id
        case .replacement(let replacement): return replacement.id
        case .new, .newReplacement: return nil
        }
    }

    private var otherWords: [String] { library.terms.filter { $0.id != editingID }.map(\.text) }
    private var otherFroms: [String] { library.replacements.filter { $0.id != editingID }.map(\.from) }

    private var canSave: Bool {
        if draft.isReplacement {
            return DictionaryRules.isValid(draft.from, others: otherFroms) && DictionaryRules.isValid(draft.to, others: [])
        }
        return DictionaryRules.isValid(draft.text, others: otherWords)
    }

    private var title: String {
        if isNew { return draft.isReplacement ? "Add replacement" : "Add word" }
        return draft.isReplacement ? "Edit replacement" : "Edit word"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(Color.fxInk)

            if isNew {
                Picker("", selection: $draft.isReplacement) {
                    Text("Word").tag(false)
                    Text("Replacement").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            if draft.isReplacement {
                replacementFields
            } else {
                wordFields
            }

            DictionarySheetButtons(canSave: canSave,
                                   onDelete: isNew ? nil : { delete() },
                                   onCancel: close,
                                   onSave: { save() })
                .padding(.top, 4)
        }
        .padding(22)
        .frame(width: 420)
        .background(Color.fxCard)
    }

    private var wordFields: some View {
        let error = DictionaryRules.problem(draft.text, others: otherWords)
        return VStack(alignment: .leading, spacing: 14) {
            DictionaryField(label: "Word", error: error) {
                DictionaryTextField(placeholder: "e.g. Jakmall", text: $draft.text, invalid: error != nil)
            }
            DictionaryField(label: "Category") {
                Picker("", selection: $draft.category) {
                    ForEach(TermCategory.allCases) { Text($0.label).tag($0) }
                }
                .labelsHidden()
                .frame(width: 180, alignment: .leading)
            }
            Text("Foxtation spells this exactly as you type it here.")
                .font(FXFont.caption).foregroundStyle(Color.fxSecondary)
        }
    }

    private var replacementFields: some View {
        let fromError = DictionaryRules.problem(draft.from, others: otherFroms)
        let toError = DictionaryRules.problem(draft.to, others: [])
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                DictionaryField(label: "When I say", error: fromError) {
                    DictionaryTextField(placeholder: "e.g. btw", text: $draft.from, invalid: fromError != nil)
                }
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.fxAccent)
                    .padding(.top, 30)
                DictionaryField(label: "Write", error: toError) {
                    DictionaryTextField(placeholder: "e.g. by the way", text: $draft.to, invalid: toError != nil)
                }
            }
            DictionaryField(label: "Where") {
                Picker("", selection: $draft.scope) {
                    Text("All apps").tag(StyleGroup?.none)
                    ForEach(StyleGroup.allCases) { Text("\($0.label) only").tag(StyleGroup?.some($0)) }
                }
                .labelsHidden()
                .frame(width: 200, alignment: .leading)
            }
            Text("Swapped on this Mac after cleanup, whole words only.")
                .font(FXFont.caption).foregroundStyle(Color.fxSecondary)
        }
    }

    private func save() {
        guard canSave else { return }
        // A new entry may have switched kind; an edit keeps its kind and ID.
        if draft.isReplacement {
            var replacement = Replacement(from: DictionaryRules.clean(draft.from), to: DictionaryRules.clean(draft.to), scope: draft.scope)
            if let id = editingID, let index = library.replacements.firstIndex(where: { $0.id == id }) {
                replacement.id = id
                library.replacements[index] = replacement
            } else {
                library.replacements.append(replacement)
            }
        } else {
            var term = Term(text: DictionaryRules.clean(draft.text), category: draft.category)
            if let id = editingID, let index = library.terms.firstIndex(where: { $0.id == id }) {
                term.id = id
                library.terms[index] = term
            } else {
                library.terms.append(term)
            }
        }
        close()
    }

    private func delete() {
        if let id = editingID {
            library.terms.removeAll { $0.id == id }
            library.replacements.removeAll { $0.id == id }
        }
        close()
    }
}

/// The editor's fields while the sheet is open.
final class DictionaryDraft: ObservableObject {
    @Published var isReplacement = false
    @Published var text = ""
    @Published var category: TermCategory = .name
    @Published var from = ""
    @Published var to = ""
    @Published var scope: StyleGroup?

    init(target: DictionaryEditTarget) {
        switch target {
        case .new: break
        case .newReplacement: isReplacement = true
        case .term(let term):
            text = term.text
            category = term.category
        case .replacement(let replacement):
            isReplacement = true
            from = replacement.from
            to = replacement.to
            scope = replacement.scope
        }
    }
}
