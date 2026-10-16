import AppKit
import UniformTypeIdentifiers

/// Small add/edit dialogs, built on NSAlert so they behave like any Mac dialog.
enum Editors {

    /// Add or edit a dictionary word. Filling in "Replaces" makes it a replacement.
    static func dictionaryEntry(_ entry: DictionaryEntry?) -> DictionaryEntry? {
        var entry = entry ?? DictionaryEntry(text: "")
        let alert = NSAlert()
        alert.messageText = entry.text.isEmpty ? "Add to dictionary" : "Edit dictionary entry"
        alert.informativeText = "Leave “Replaces” empty to add a word Foxtation should always spell this way."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let text = field(entry.text, placeholder: "Khaisa Studio")
        let from = field(entry.from, placeholder: "optional, e.g. btw")
        let category = NSPopUpButton()
        category.addItems(withTitles: WordCategory.allCases.map(\.label))
        category.selectItem(at: WordCategory.allCases.firstIndex(of: entry.category) ?? 0)
        let scope = NSPopUpButton()
        scope.addItems(withTitles: ["All apps"] + StyleGroup.allCases.map { "\($0.label) only" })
        scope.selectItem(at: entry.scope.flatMap { StyleGroup.allCases.firstIndex(of: $0) }.map { $0 + 1 } ?? 0)

        alert.accessoryView = form([
            ("Word or phrase", text),
            ("Replaces", from),
            ("Category", category),
            ("Replacement applies in", scope),
        ])
        alert.window.initialFirstResponder = text
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        entry.text = text.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.from = from.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.category = WordCategory.allCases[category.indexOfSelectedItem]
        entry.scope = scope.indexOfSelectedItem == 0 ? nil : StyleGroup.allCases[scope.indexOfSelectedItem - 1]
        return entry.text.isEmpty ? nil : entry
    }

    static func snippet(_ snippet: Snippet?) -> Snippet? {
        var snippet = snippet ?? Snippet(cue: "", expansion: "")
        let alert = NSAlert()
        alert.messageText = snippet.cue.isEmpty ? "New snippet" : "Edit snippet"
        alert.informativeText = "Say the cue while dictating and Foxtation pastes the full text in its place."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let cue = field(snippet.cue, placeholder: "my email")
        let expansion = NSTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        expansion.string = snippet.expansion
        expansion.font = .systemFont(ofSize: 13)
        expansion.isRichText = false
        expansion.autoresizingMask = [.width]
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 300, height: 90))
        scroll.documentView = expansion
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 90).isActive = true

        alert.accessoryView = form([("Cue", cue), ("Expands to", scroll)])
        alert.window.initialFirstResponder = cue
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }

        snippet.cue = cue.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        snippet.expansion = expansion.string
        return snippet.cue.isEmpty || snippet.expansion.isEmpty ? nil : snippet
    }

    /// Picks an app from /Applications.
    static func chooseApp() -> AppRef? {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return nil }
        let name = FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        return AppRef(bundleID: bundleID, name: name)
    }

    static func confirmDelete(_ what: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Delete “\(what)”?"
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: - Layout

    private static func field(_ value: String, placeholder: String) -> NSTextField {
        let field = NSTextField(string: value)
        field.placeholderString = placeholder
        return field
    }

    private static func form(_ rows: [(String, NSView)]) -> NSView {
        let grid = NSGridView(views: rows.map { title, control in
            let label = NSTextField(labelWithString: title + ":")
            label.alignment = .right
            return [label, control]
        })
        grid.column(at: 0).xPlacement = .trailing
        grid.rowAlignment = .firstBaseline
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        for (_, control) in rows {
            control.translatesAutoresizingMaskIntoConstraints = false
            control.widthAnchor.constraint(equalToConstant: 260).isActive = true
        }
        grid.frame = NSRect(origin: .zero, size: grid.fittingSize)
        return grid
    }
}
