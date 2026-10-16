import AppKit
import SwiftUI

// Small building blocks shared by every screen of the main window. Layout
// follows docs/design; colors come only from `Palette` (see Theme.swift).

enum FXFont {
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let detail = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let bigNumber = Font.system(size: 26, weight: .semibold).monospacedDigit()
    static let mono = Font.system(size: 12, design: .monospaced)
}

/// A white card with a hairline border.
struct FXCard<Content: View>: View {
    var padding: CGFloat = 16
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxCard))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.fxSeparator))
    }
}

/// Title (+ optional subtitle) on the left, actions on the right.
struct PageHeader<Trailing: View>: View {
    var title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(FXFont.pageTitle).foregroundStyle(Color.fxInk)
                if let subtitle {
                    Text(subtitle).font(FXFont.body).foregroundStyle(Color.fxSecondary)
                }
            }
            Spacer()
            trailing
        }
    }
}

extension PageHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// "WORDS TODAY"-style small caps label.
struct SectionLabel: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(FXFont.sectionLabel)
            .kerning(0.4)
            .foregroundStyle(Color.fxSecondary)
    }
}

/// A big number with a caption and optional unit.
struct StatTile: View {
    var title: String
    var value: String
    var unit: String?

    var body: some View {
        FXCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(value).font(FXFont.bigNumber).foregroundStyle(Color.fxInk)
                    if let unit { Text(unit).font(FXFont.detail).foregroundStyle(Color.fxSecondary) }
                }
            }
        }
    }
}

/// Settings-style row: title and detail on the left, a control on the right.
struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(FXFont.body.weight(.medium)).foregroundStyle(Color.fxInk)
                if let detail {
                    Text(detail).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Rows inside one card. Put a `RowDivider()` between rows.
struct RowsCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.fxCard))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.fxSeparator))
    }
}

/// The hairline between rows of a card or list.
struct RowDivider: View {
    var body: some View { Rectangle().fill(Color.fxSeparator).frame(height: 1) }
}

/// The palette's switch.
struct FXSwitch: View {
    @Binding var isOn: Bool
    var body: some View {
        SwiftUI.Toggle("", isOn: $isOn).toggleStyle(.switch).labelsHidden().tint(Color.fxAccent).controlSize(.small)
    }
}

enum FXButtonKind { case primary, dark, secondary, destructive, plain }

/// Buttons in the design's four weights.
struct FXButtonStyle: ButtonStyle {
    var kind: FXButtonKind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(FXFont.body.weight(.medium))
            .padding(.horizontal, compact ? 10 : 14)
            .padding(.vertical, compact ? 5 : 7)
            .foregroundStyle(foreground)
            .background(RoundedRectangle(cornerRadius: 7).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(border))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 7))
    }

    private var foreground: Color {
        switch kind {
        case .primary, .dark: return .fxCard
        case .secondary, .plain: return .fxInk
        case .destructive: return .fxBad
        }
    }

    private var fill: Color {
        switch kind {
        case .primary: return .fxAccent
        case .dark: return .fxInk
        case .secondary, .destructive: return .fxCard
        case .plain: return .clear
        }
    }

    private var border: Color {
        switch kind {
        case .secondary: return .fxSeparator
        case .destructive: return .fxBad.opacity(0.35)
        case .primary, .dark, .plain: return .clear
        }
    }
}

extension View {
    func fxButton(_ kind: FXButtonKind = .secondary, compact: Bool = false) -> some View {
        buttonStyle(FXButtonStyle(kind: kind, compact: compact))
    }
}

/// A rounded tag, optionally removable or tappable.
struct Chip: View {
    var text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Text(text).font(FXFont.detail.weight(.medium)).foregroundStyle(Color.fxInk)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.fxSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(Color.fxCard))
        .overlay(Capsule().strokeBorder(Color.fxSeparator))
    }
}

/// Text tabs with an underline under the selected one (Dictionary, Style).
struct UnderlineTabs<Value: Hashable>: View {
    @Binding var selection: Value
    var items: [(Value, String)]

    var body: some View {
        HStack(spacing: 20) {
            ForEach(items.indices, id: \.self) { index in
                let (value, title) = items[index]
                Button { selection = value } label: {
                    VStack(spacing: 7) {
                        Text(title)
                            .font(FXFont.body.weight(selection == value ? .semibold : .regular))
                            .foregroundStyle(selection == value ? Color.fxInk : Color.fxSecondary)
                        Rectangle().fill(selection == value ? Color.fxInk : Color.clear).frame(height: 2)
                    }
                    .fixedSize()
                }
                .buttonStyle(.plain)
            }
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color.fxSeparator).frame(height: 1).offset(y: 0.5) }
    }
}

/// A pill-shaped segmented picker (Insights' 7 days / 30 days / All time).
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    var items: [(Value, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(items.indices, id: \.self) { index in
                let (value, title) = items[index]
                Button { selection = value } label: {
                    Text(title)
                        .font(FXFont.detail.weight(.medium))
                        .foregroundStyle(selection == value ? Color.fxInk : Color.fxSecondary)
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6).fill(selection == value ? Color.fxCard : .clear))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.fxWash))
    }
}

/// A thin progress bar.
struct UsageBar: View {
    var fraction: Double
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.fxTrack)
                Capsule().fill(Color.fxAccent).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 5)
    }
}

/// A small colored dot that stays the same for an app across screens.
struct AppDot: View {
    var app: String
    static let colors: [Color] = [.fxAccent, .fxGood, .fxBad, .fxInk, .fxSecondary]

    var body: some View {
        Circle().fill(Self.color(for: app)).frame(width: 6, height: 6)
    }

    static func color(for app: String) -> Color {
        let hash = app.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF }
        return colors[hash % colors.count]
    }
}

/// Initials in a circle.
struct Avatar: View {
    var name: String
    var body: some View {
        Text(Self.initials(name))
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(Color.fxCard)
            .frame(width: 26, height: 26)
            .background(Circle().fill(Color.fxInk))
    }

    static func initials(_ name: String) -> String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }
}

/// A keyboard key, like the design's `fn` cap.
struct KeyCap: View {
    var text: String
    var body: some View {
        Text(text)
            .font(FXFont.mono)
            .foregroundStyle(Color.fxInk)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.fxWash))
            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.fxSeparator))
    }
}

/// Shown by pages that aren't built yet.
struct PagePlaceholder: View {
    var title: String
    var body: some View {
        VStack(alignment: .leading) {
            PageHeader(title: title)
            Spacer()
        }
    }
}

enum Format {
    static func number(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// "18:42"
    static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    /// "12 Oct 2026"
    static func day(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "d MMM yyyy"
        formatter.locale = Locale(identifier: "en_GB")
        return formatter.string(from: date)
    }

    /// "212 MB"
    static func bytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    /// "6h 08m" / "24 min"
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return String(format: "%dh %02dm", total / 60, total % 60)
    }
}
