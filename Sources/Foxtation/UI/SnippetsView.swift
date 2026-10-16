import SwiftUI

struct SnippetsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var library: Library

    var body: some View {
        let snippets = library.snippets.sorted { $0.used > $1.used }
        let examples = snippets.count >= 2
            ? snippets.prefix(2).map { ($0.cue, $0.expansion) }
            : [("alamat kantor", "[YOUR OFFICE ADDRESS]"), ("standup", "Kemarin: … Hari ini: … Blocker: …")]

        PageColumn {
            PageTitle(title: "Snippets") {
                Button { edit(nil) } label: { Label("New snippet", systemImage: "plus") }
                    .buttonStyle(FxButtonStyle(kind: .dark, height: 36))
            }

            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Say a cue. Drop the whole text.").font(.system(size: 22, weight: .semibold)).tracking(-0.4)
                    Text("Save anything you type often — an address, a standup template, a prompt. Speak its cue mid-sentence and Foxtation pastes it in.")
                        .font(.system(size: 13.5))
                        .lineSpacing(3)
                        .foregroundStyle(Fx.card.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(examples, id: \.0) { cue, expansion in
                        HStack(spacing: 10) {
                            Text("“\(cue)”").italic()
                                .fixedSize()
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Fx.card.opacity(0.16)))
                            Image(systemName: "arrow.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Fx.card.opacity(0.6))
                            Text(expansion.replacingOccurrences(of: "\n", with: " "))
                                .lineLimit(1)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).fill(Fx.card.opacity(0.06)))
                                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Fx.card.opacity(0.16), lineWidth: 1))
                        }
                        .font(.system(size: 13))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(Fx.card)
            .padding(.horizontal, 28)
            .padding(.vertical, 26)
            .background(RoundedRectangle(cornerRadius: 14).fill(Fx.ink))

            VStack(spacing: 0) {
                HStack(spacing: 16) {
                    Text("Cue").frame(width: 180, alignment: .leading)
                    Text("Expands to").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Used").frame(width: 70, alignment: .trailing)
                    Color.clear.frame(width: 60, height: 1)
                }
                .font(.system(size: 12, weight: .medium))
                .tracking(0.5)
                .textCase(.uppercase)
                .foregroundStyle(Fx.secondary)
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
                Hairline()
                if snippets.isEmpty {
                    Text("No snippets yet. Add your email, an address or a prompt you paste every day.")
                        .font(.system(size: 13.5))
                        .foregroundStyle(Fx.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 20)
                        .padding(.horizontal, 8)
                }
                ForEach(snippets) { snippet in
                    row(snippet)
                    if snippet.id != snippets.last?.id { Hairline() }
                }
            }
        }
    }

    private func row(_ snippet: Snippet) -> some View {
        let hovered = model.hoveredRow == snippet.id
        return HStack(spacing: 16) {
            Text(snippet.cue).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                .frame(width: 180, alignment: .leading)
            Text(snippet.expansion.replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 13.5)).foregroundStyle(Fx.ink.opacity(0.85)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("\(snippet.used)×").font(Fx.mono(12)).foregroundStyle(Fx.secondary)
                .frame(width: 70, alignment: .trailing)
            HStack(spacing: 0) {
                IconButton(symbol: "pencil", label: "Edit") { edit(snippet) }
                IconButton(symbol: "trash", label: "Delete") {
                    library.snippets.removeAll { $0.id == snippet.id }
                    library.saveSnippets()
                }
            }
            .frame(width: 60, alignment: .trailing)
            .opacity(hovered ? 1 : 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .background(hovered ? Fx.wash : .clear)
        .contentShape(Rectangle())
        .onHover { inside in
            if inside { model.hoveredRow = snippet.id } else if model.hoveredRow == snippet.id { model.hoveredRow = nil }
        }
    }

    private func edit(_ existing: Snippet?) {
        guard let snippet = Editors.snippet(existing) else { return }
        if let index = library.snippets.firstIndex(where: { $0.id == snippet.id }) {
            library.snippets[index] = snippet
        } else {
            library.snippets.append(snippet)
        }
        library.saveSnippets()
    }
}
