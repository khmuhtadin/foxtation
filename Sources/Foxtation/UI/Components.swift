import AppKit
import SwiftUI

// SwiftUI without macros: Command Line Tools don't ship the SwiftUI macro
// plugin, so `@State` and `#Preview` are out. View state lives in
// ObservableObjects (AppModel, Settings, Library) passed in as @ObservedObject.

/// The app's palette (see `Palette`) as SwiftUI colors.
enum Fx {
    static let background = Color(nsColor: Palette.background)
    static let card = Color(nsColor: Palette.card)
    static let ink = Color(nsColor: Palette.ink)
    static let secondary = Color(nsColor: Palette.secondary)
    static let separator = Color(nsColor: Palette.separator)
    static let accent = Color(nsColor: Palette.accent)
    static let track = Color(nsColor: Palette.track)
    static let good = Color(nsColor: Palette.good)
    static let bad = Color(nsColor: Palette.bad)

    /// Subtle fill inside a card: segmented controls, example boxes, hover.
    static let wash = Color(nsColor: Palette.background).opacity(0.6)

    static func mono(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// A stable color per app name for the little dots in history rows.
    static func appColor(_ name: String) -> Color {
        let colors = [accent, good, bad, secondary, ink]
        let sum = name.unicodeScalars.reduce(0) { $0 + Int($1.value) }
        return colors[sum % colors.count]
    }
}

extension View {
    /// White card with a hairline border, as used across the design.
    func card(radius: CGFloat = 12) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(Fx.card))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Fx.separator, lineWidth: 1))
    }

    /// Bordered box with no fill, sitting on a card.
    func outlined(radius: CGFloat = 12) -> some View {
        overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Fx.separator, lineWidth: 1))
    }
}

/// The section heading style: small, uppercase, tracked.
struct Eyebrow: View {
    var text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .medium))
            .tracking(0.7)
            .foregroundStyle(Fx.secondary)
    }
}

/// A key cap, e.g. the trigger key in "Hold [right ⌥] anywhere to dictate".
struct Kbd: View {
    var text: String
    var size: CGFloat = 12
    var body: some View {
        Text(text)
            .font(Fx.mono(size))
            .foregroundStyle(Fx.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 5).fill(Fx.wash))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Fx.track, lineWidth: 1))
    }
}

/// On/off switch in the accent color.
struct FxToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Capsule()
            .fill(isOn ? Fx.accent : Fx.track)
            .frame(width: 36, height: 22)
            .overlay(alignment: isOn ? .trailing : .leading) {
                Circle().fill(Color.white)
                    .frame(width: 18, height: 18)
                    .shadow(color: .black.opacity(0.2), radius: 1, y: 1)
                    .padding(2)
            }
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.easeOut(duration: 0.15)) { isOn.toggle() } }
            .accessibilityElement()
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isOn ? "on" : "off")
            .accessibilityAction { isOn.toggle() }
    }
}

enum FxButtonKind { case plain, primary, dark, danger }

/// Buttons from the design: outlined (plain), filled accent (primary),
/// filled ink (dark) and outlined red (danger).
struct FxButtonStyle: ButtonStyle {
    var kind: FxButtonKind = .plain
    var height: CGFloat = 32

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .lineLimit(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: height)
            .background(RoundedRectangle(cornerRadius: 8).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(border, lineWidth: 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Rectangle())
            .fixedSize()
    }

    private var foreground: Color {
        switch kind {
        case .plain: return Fx.ink
        case .primary: return .white
        case .dark: return Fx.card
        case .danger: return Fx.bad
        }
    }

    private var fill: Color {
        switch kind {
        case .plain, .danger: return Fx.card
        case .primary: return Fx.accent
        case .dark: return Fx.ink
        }
    }

    private var border: Color {
        switch kind {
        case .plain: return Fx.track
        case .danger: return Fx.bad.opacity(0.35)
        case .primary, .dark: return .clear
        }
    }
}

/// A square, borderless icon button.
struct IconButton: View {
    var symbol: String
    var label: String
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(Fx.secondary)
                .frame(width: 30, height: 30)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}

/// Thin rounded progress bar.
struct Meter: View {
    var fraction: Double
    var height: CGFloat = 6
    var color = Fx.accent
    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Fx.wash)
                Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: height)
    }
}

/// Pill-shaped segmented control (Insights range).
struct Segments<T: Hashable>: View {
    var options: [(T, String)]
    @Binding var selection: T
    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.0) { value, title in
                let selected = value == selection
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(selected ? Fx.ink : Fx.secondary)
                    .padding(.horizontal, 12)
                    .frame(height: 28)
                    .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Fx.card : .clear)
                        .shadow(color: .black.opacity(selected ? 0.08 : 0), radius: 1, y: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { selection = value }
            }
        }
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Fx.background))
    }
}

/// Underlined tabs over a hairline (Dictionary filter, Style groups).
struct UnderlineTabs<T: Hashable, Trailing: View>: View {
    var options: [(T, String, String?)]
    @Binding var selection: T
    var spacing: CGFloat = 22
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: spacing) {
            ForEach(options, id: \.0) { value, title, count in
                let selected = value == selection
                HStack(spacing: 4) {
                    Text(title).font(.system(size: 13.5, weight: .medium))
                    if let count { Text(count).font(.system(size: 13.5)).foregroundStyle(Fx.secondary) }
                }
                .foregroundStyle(selected ? Fx.ink : Fx.secondary)
                .frame(height: 34)
                .padding(.horizontal, 2)
                .overlay(alignment: .bottom) { Rectangle().fill(selected ? Fx.ink : .clear).frame(height: 2) }
                .contentShape(Rectangle())
                .onTapGesture { selection = value }
            }
            Spacer(minLength: 0)
            trailing().padding(.bottom, 6)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Fx.separator).frame(height: 1) }
    }
}

/// A settings line: title and detail on the left, a control on the right.
struct SettingRow<Trailing: View>: View {
    var title: String
    var detail: String?
    /// Used instead of `detail` when the line needs more than text, e.g. a key cap.
    var detailView: AnyView?
    var verticalPadding: CGFloat = 16
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 24) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Fx.ink)
                if let detailView {
                    detailView
                } else if let detail {
                    Text(detail).font(.system(size: 13)).foregroundStyle(Fx.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, verticalPadding)
    }
}

/// Rows stacked in an outlined box; put a `Hairline()` between rows.
struct RowGroup<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: 0) { content() }
            .outlined()
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Fx.separator).frame(height: 1) }
}

/// The app icon as a small rounded tile.
struct AppMark: View {
    var size: CGFloat = 28
    static let image: NSImage? = {
        if let url = Bundle.main.url(forResource: "AppIcon", withExtension: "icns") { return NSImage(contentsOf: url) }
        let local = URL(fileURLWithPath: "Resources/AppIcon.icns")  // `swift run` from the repo
        return NSImage(contentsOf: local)
    }()

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image).resizable().interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.28).fill(Fx.accent)
            }
        }
        .frame(width: size, height: size)
    }
}
