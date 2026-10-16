import AppKit
import SwiftUI

/// One dictation in a list: time · app · pasted text. Hovering shows play,
/// copy and a ⋯ menu. Used by Home's TODAY list and the History page.
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
                .font(FXFont.mono)
                .foregroundStyle(Color.fxSecondary)
                .frame(width: 44, alignment: .leading)
            HStack(spacing: 7) {
                AppDot(app: dictation.app)
                Text(dictation.app.isEmpty ? "Unknown" : dictation.app)
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxInk)
                    .lineLimit(1)
            }
            .frame(width: 92, alignment: .leading)
            Text(dictation.text)
                .font(FXFont.body)
                .foregroundStyle(Color.fxInk)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if hovering { actions }
        }
        .padding(.horizontal, 16)
        .frame(height: 52)
        .background(hovering ? Color.fxWash : Color.clear)
        .contentShape(Rectangle())
        .onHover { hoveringState.wrappedValue = $0 }
    }

    private var actions: some View {
        HStack(spacing: 4) {
            if let url = model.history.audioURL(for: dictation) {
                iconButton("play", label: "Play recording") { HistoryAudio.play(url) }
            }
            iconButton(copied ? "checkmark" : "doc.on.doc", label: "Copy text") {
                HistoryRow.copy(dictation.text)
                copiedState.wrappedValue = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copiedState.wrappedValue = false }
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
            .frame(width: 24, height: 24)
            .accessibilityLabel("More")
        }
        .foregroundStyle(Color.fxSecondary)
    }

    private func iconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.fxSecondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
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
        FXCard(padding: 28) {
            VStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 20))
                    .foregroundStyle(Color.fxSecondary)
                Text(title).font(FXFont.body.weight(.medium)).foregroundStyle(Color.fxInk)
                Text(detail).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
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
