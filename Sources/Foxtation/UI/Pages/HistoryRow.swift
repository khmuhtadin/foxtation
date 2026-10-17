import AppKit
import SwiftUI

/// One dictation in a list: time · app · pasted text. Hovering shows play,
/// copy and a ⋯ menu over the end of the text, so the text never reflows;
/// right-click offers the same actions. Used by Home's TODAY list and History.
struct HistoryRow: View {
    @ObservedObject var model: AppModel
    var dictation: Dictation
    // Plain `State` values: this toolchain has no SwiftUI macro plugin for `@State`.
    private let hoveringState = State(initialValue: false)
    private let copiedState = State(initialValue: false)
    private var hovering: Bool { hoveringState.wrappedValue }
    private var copied: Bool { copiedState.wrappedValue }

    var body: some View {
        HStack(spacing: 16) {
            Text(Format.time(dictation.date))
                .font(FXFont.number)
                .foregroundStyle(Color.fxSecondary)
                .frame(width: 40, alignment: .leading)
            HStack(spacing: 7) {
                AppDot(app: dictation.app)
                Text(appName)
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxInk)
                    .lineLimit(1)
                    .help(appName)
            }
            .frame(width: 96, alignment: .leading)
            Text(dictation.text)
                .font(FXFont.body)
                .foregroundStyle(Color.fxInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(dictation.text)
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .overlay(alignment: .trailing) {
            if hovering {
                actions
                    .padding(.leading, 12)
                    .padding(.trailing, 10)
                    .frame(maxHeight: .infinity)
                    .background(Color.fxWash)
            }
        }
        .background(hovering ? Color.fxWash : Color.clear)
        .contentShape(Rectangle())
        .onHover { hoveringState.wrappedValue = $0 }
        .contextMenu {
            Button("Copy text") { HistoryRow.copy(dictation.text) }
            Button("Copy raw transcript") { HistoryRow.copy(dictation.raw) }
            Divider()
            Button("Delete", role: .destructive) { model.history.delete(dictation.id) }
        }
    }

    private var appName: String { dictation.app.isEmpty ? "Unknown" : dictation.app }

    private var actions: some View {
        HStack(spacing: 2) {
            if let url = model.history.audioURL(for: dictation) {
                IconButton(symbol: "play", label: "Play recording") { HistoryAudio.play(url) }
            }
            IconButton(symbol: copied ? "checkmark" : "doc.on.doc", label: "Copy text") {
                HistoryRow.copy(dictation.text)
                copiedState.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copiedState.wrappedValue = false }
            }
            Menu {
                Button("Copy raw transcript") { HistoryRow.copy(dictation.raw) }
                Divider()
                Button("Delete", role: .destructive) { model.history.delete(dictation.id) }
            } label: {
                Image(systemName: "ellipsis")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .frame(width: 28, height: 28)
            .help("More")
            .accessibilityLabel("More")
        }
        .foregroundStyle(Color.fxSecondary)
    }

    static func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Rows in a card, with hairlines between them.
struct HistoryRowsCard: View {
    @ObservedObject var model: AppModel
    var dictations: [Dictation]

    var body: some View {
        RowsCard {
            ForEach(Array(dictations.enumerated()), id: \.element.id) { index, dictation in
                if index > 0 { RowDivider() }
                HistoryRow(model: model, dictation: dictation)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

/// An empty list: a symbol, a line and a hint, inside a card.
struct HistoryEmptyCard: View {
    var symbol: String
    var title: String
    var detail: String

    var body: some View {
        FXCard(padding: 32) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fxSecondary)
                    .padding(.bottom, 4)
                Text(title).font(FXFont.cardTitle).foregroundStyle(Color.fxInk)
                Text(detail).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Plays a kept recording; starting another one stops the first.
enum HistoryAudio {
    private static var sound: NSSound?

    static func play(_ url: URL) {
        sound?.stop()
        sound = NSSound(contentsOf: url, byReference: true)
        sound?.play()
    }
}
