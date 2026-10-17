import AppKit
import SwiftUI

// Small building blocks shared by every screen of the main window. Layout
// follows docs/design; colors come only from `Palette` (see Theme.swift).

/// The window's type scale. Sizes outside it need a reason.
enum FXFont {
    static let pageTitle = Font.system(size: 22, weight: .semibold)
    /// Sheet titles and intro cards.
    static let headline = Font.system(size: 15, weight: .semibold)
    static let cardTitle = Font.system(size: 13, weight: .semibold)
    static let body = Font.system(size: 13)
    static let detail = Font.system(size: 12)
    static let caption = Font.system(size: 11)
    static let sectionLabel = Font.system(size: 11, weight: .semibold)
    static let bigNumber = Font.system(size: 28, weight: .semibold).monospacedDigit()
    /// Times, counts and percentages: equal-width digits, so columns line up.
    static let number = Font.system(size: 12).monospacedDigit()
    /// License keys and key caps.
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
        FXCard(padding: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(FXFont.detail).foregroundStyle(Color.fxSecondary)
                BigNumber(value: value, unit: unit)
            }
        }
    }
}

/// "142 wpm": a stat number with its unit, as on Home and Insights.
struct BigNumber: View {
    var value: String
    var unit: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(value).font(FXFont.bigNumber).foregroundStyle(Color.fxInk)
            if let unit { Text(unit).font(FXFont.body).foregroundStyle(Color.fxSecondary) }
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

/// The palette's switch. Drawn like the AppKit `Toggle` in the Engine pane, so
/// both look the same and read on or off whether or not the window is key.
struct FXSwitch: View {
    /// What it switches, for VoiceOver (usually the row title).
    var label: String
    @Binding var isOn: Bool
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Button { isOn.toggle() } label: {
            Capsule()
                .fill(isOn ? Color.fxAccent : Color.fxTrack)
                .frame(width: 34, height: 20)
                .overlay(alignment: isOn ? .trailing : .leading) {
                    Circle().fill(Color.white)
                        .shadow(color: .black.opacity(0.2), radius: 1, y: 0.5)
                        .frame(width: 16, height: 16)
                        .padding(2)
                }
                .padding(.vertical, 4)  // a 28pt tall hit area
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.45)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? "On" : "Off")
        .accessibilityAddTraits(.isToggle)
    }
}

enum FXButtonKind { case primary, dark, secondary, destructive }

/// Buttons in the design's four weights. At least 28pt tall, with a hover fill
/// and a small press-in (only a dim with Reduce Motion on).
struct FXButtonStyle: ButtonStyle {
    var kind: FXButtonKind = .secondary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        StyledBody(configuration: configuration, style: self)
    }

    /// A view, so it can read the environment and track hover.
    private struct StyledBody: View {
        var configuration: Configuration
        var style: FXButtonStyle
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        // Plain `State`: this toolchain has no SwiftUI macro plugin for `@State`.
        private let hoverState = State(initialValue: false)

        var body: some View {
            let pressed = configuration.isPressed
            configuration.label
                .font(FXFont.body.weight(.medium))
                .padding(.horizontal, style.compact ? 10 : 14)
                .frame(minHeight: style.compact ? 28 : 30)
                .foregroundStyle(style.foreground)
                .background(RoundedRectangle(cornerRadius: 7).fill(style.fill(hovered: hoverState.wrappedValue && isEnabled)))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(style.border))
                .contentShape(RoundedRectangle(cornerRadius: 7))
                .opacity(isEnabled ? (pressed ? 0.8 : 1) : 0.45)
                .scaleEffect(pressed && !reduceMotion ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: pressed)
                .onHover { hoverState.wrappedValue = $0 }
        }
    }

    private var foreground: Color {
        switch kind {
        case .primary, .dark: return .fxCard
        case .secondary: return .fxInk
        case .destructive: return .fxBad
        }
    }

    private func fill(hovered: Bool) -> Color {
        switch kind {
        case .primary: return Color.fxAccent.opacity(hovered ? 0.9 : 1)
        case .dark: return Color.fxInk.opacity(hovered ? 0.88 : 1)
        case .secondary, .destructive: return hovered ? .fxWash : .fxCard
        }
    }

    private var border: Color {
        switch kind {
        case .secondary: return .fxSeparator
        case .destructive: return .fxBad.opacity(0.35)
        case .primary, .dark: return .clear
        }
    }
}

extension View {
    func fxButton(_ kind: FXButtonKind = .secondary, compact: Bool = false) -> some View {
        buttonStyle(FXButtonStyle(kind: kind, compact: compact))
    }
}

/// A borderless symbol button: 28pt hit area, hover fill, tooltip and a
/// VoiceOver label.
struct IconButton: View {
    var symbol: String
    var label: String
    var size: CGFloat = 11
    var action: () -> Void
    private let hoverState = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(Color.fxSecondary)
                .frame(width: 28, height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(hoverState.wrappedValue ? Color.fxInk.opacity(0.07) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .help(label)
        .accessibilityLabel(label)
    }
}

/// An accent text button ("View all", "‹ Home"), 28pt tall so it's easy to hit.
/// Underlines on hover, like a link.
struct TextLink: View {
    var title: String
    /// Drawn before the title, e.g. "chevron.left".
    var symbol: String?
    var action: () -> Void
    private let hoverState = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { Image(systemName: symbol).font(.system(size: 10, weight: .semibold)) }
                Text(title).underline(hoverState.wrappedValue)
            }
            .font(FXFont.detail.weight(.medium))
            .foregroundStyle(Color.fxAccent)
            .frame(height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
    }
}

/// A row of the window sidebar and the Settings list. Selection is a card
/// fill; the text weight stays the same, so nothing shifts when it moves.
struct NavRow: View {
    var title: String
    var symbol: String
    var selected: Bool
    var action: () -> Void
    private let hoverState = State(initialValue: false)

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .frame(width: 16)
                    .foregroundStyle(selected ? Color.fxInk : Color.fxSecondary)
                Text(title).font(FXFont.body).foregroundStyle(Color.fxInk)
                Spacer()
            }
            .padding(.horizontal, 8)
            .frame(height: 28)
            .background(RoundedRectangle(cornerRadius: 7).fill(
                selected ? Color.fxCard : hoverState.wrappedValue ? Color.fxInk.opacity(0.05) : .clear))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.fxSeparator : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hoverState.wrappedValue = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The window's search box: magnifier, field, and a clear button once there's
/// text. Fixed height, so the clear button doesn't nudge anything.
struct SearchField: View {
    var placeholder: String
    @Binding var text: String
    var width: CGFloat = 220

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.fxSecondary)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(FXFont.body)
                .foregroundStyle(Color.fxInk)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(Color.fxSecondary)
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Clear search")
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.fxWash))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.fxSeparator))
    }
}

/// A rounded tag, optionally removable.
struct Chip: View {
    var text: String
    var onRemove: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            Text(text).font(FXFont.detail.weight(.medium)).foregroundStyle(Color.fxInk)
            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).foregroundStyle(Color.fxSecondary)
                        .frame(width: 18, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Remove \(text)")
                .accessibilityLabel("Remove \(text)")
            }
        }
        .padding(.leading, 10)
        .padding(.trailing, onRemove == nil ? 10 : 4)
        .frame(height: 26)
        .background(Capsule().fill(Color.fxCard))
        .overlay(Capsule().strokeBorder(Color.fxSeparator))
    }
}

/// Text tabs with an underline under the selected one (Dictionary, Style). The
/// parent draws the hairline under the whole row. The weight never changes, so
/// switching tabs doesn't shift the labels.
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
                            .font(FXFont.body.weight(.medium))
                            .foregroundStyle(selection == value ? Color.fxInk : Color.fxSecondary)
                        Rectangle().fill(selection == value ? Color.fxInk : Color.clear).frame(height: 2)
                    }
                    .padding(.top, 6)
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
            }
        }
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
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(RoundedRectangle(cornerRadius: 5).fill(selection == value ? Color.fxCard : .clear))
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selection == value ? Color.fxSeparator : .clear))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selection == value ? .isSelected : [])
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

    /// "212 MB", and "0 KB" rather than "Zero KB".
    static func bytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }

    /// "6h 08m" / "24 min"
    static func duration(minutes: Double) -> String {
        let total = Int(minutes.rounded())
        if total < 60 { return "\(total) min" }
        return String(format: "%dh %02dm", total / 60, total % 60)
    }
}
