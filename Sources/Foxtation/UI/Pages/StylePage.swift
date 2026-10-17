import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// How cleanup sounds in each kind of app, and which apps belong to each kind.
struct StylePage: View {
    @ObservedObject var model: AppModel

    @StateObject private var state = StylePageState()
    private var group: StyleGroup { state.group }

    private var library: Library { model.library }

    private var selectedStyle: CleanupStyle {
        library.groups[group]?.style ?? group.defaultStyle
    }

    private var apps: [AppRef] { library.groups[group]?.apps ?? [] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Style",
                           subtitle: "Choose how cleanup sounds in each kind of app. Foxtation detects the app you’re typing in.")
                    .padding(.bottom, 22)

                HStack {
                    UnderlineTabs(selection: $state.group, items: StyleGroup.allCases.map { ($0, $0.label) })
                    Spacer()
                }
                .overlay(alignment: .bottom) { Rectangle().fill(Color.fxSeparator).frame(height: 1).offset(y: 0.5) }
                .padding(.bottom, 22)

                HStack(alignment: .top, spacing: 12) {
                    ForEach(group.styles, id: \.self) { style in
                        StyleCard(style: style, selected: style == selectedStyle) {
                            library.groups[group]?.style = style
                        }
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 26)

                SectionLabel(text: "Apps using \(group.label) style")
                    .padding(.bottom, 10)
                StyleFlowLayout(spacing: 8) {
                    ForEach(apps) { app in
                        Chip(text: app.name) { remove(app) }
                    }
                    Button { addApps() } label: {
                        Text("+ Add app")
                            .font(FXFont.detail.weight(.medium))
                            .foregroundStyle(Color.fxAccent)
                            .padding(.horizontal, 10)
                            .frame(height: 26)
                            .overlay(Capsule().strokeBorder(Color.fxSeparator, style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 26)

                RowsCard {
                    SettingRow(title: "Keep emoji I say out loud",
                               detail: "“emoji ketawa” becomes 😂 instead of the words.") {
                        FXSwitch(label: "Keep emoji I say out loud", isOn: Binding(get: { library.spokenEmoji }, set: { library.spokenEmoji = $0 }))
                    }
                }
            }
            .frame(maxWidth: 740)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.never)
    }

    private func remove(_ app: AppRef) {
        library.groups[group]?.apps.removeAll { $0.bundleID == app.bundleID }
    }

    /// Picks .app bundles and moves them into this group.
    private func addApps() {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.prompt = "Add"
        panel.message = "Choose apps that use the \(group.label) style."
        guard panel.runModal() == .OK else { return }

        var groups = library.groups
        for url in panel.urls {
            guard let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else { continue }
            let name = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
                ?? url.deletingPathExtension().lastPathComponent
            for other in StyleGroup.allCases {
                groups[other]?.apps.removeAll { $0.bundleID == bundleID }
            }
            groups[group]?.apps.append(AppRef(bundleID: bundleID, name: name))
        }
        library.groups = groups
    }
}

final class StylePageState: ObservableObject {
    @Published var group: StyleGroup = .chat
}

/// One style option: name, what it does and an example.
struct StyleCard: View {
    var style: CleanupStyle
    var selected: Bool
    var select: () -> Void
    // Plain `State`: this toolchain has no SwiftUI macro plugin for `@State`.
    private let hoverState = State(initialValue: false)

    private var borderColor: Color {
        if selected { return .fxAccent }
        return hoverState.wrappedValue ? .fxTrack : .fxSeparator
    }

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 0) {
                Text(style.label)
                    .font(FXFont.cardTitle)
                    .foregroundStyle(Color.fxInk)
                    .padding(.bottom, 8)
                Text(style.detail)
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxSecondary)
                    .lineSpacing(2)
                    .padding(.bottom, 12)
                Spacer(minLength: 0)
                Text(style.example)
                    .font(FXFont.detail)
                    .foregroundStyle(Color.fxInk)
                    .lineSpacing(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.fxWash))
            }
            .padding(16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxCard))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(borderColor, lineWidth: selected ? 1.5 : 1))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color.fxCard)
                        .frame(width: 16, height: 16)
                        .background(Circle().fill(Color.fxAccent))
                        .padding(14)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct StyleFlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return CGSize(width: widest, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
