import AppKit
import SwiftUI

/// Colors from the app icon: ice-blue tile, white fox, indigo waveform, navy ink.
/// Light accent, good and bad are dark enough for 12pt text on a card and for
/// white text on them (WCAG AA, 4.5:1).
enum Palette {
    static let background = dynamic(light: 0xDCE7F8, dark: 0x151A33)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F2647)
    static let ink = dynamic(light: 0x1E2140, dark: 0xEEF1FF)
    static let secondary = dynamic(light: 0x5E6689, dark: 0x9AA3C9)
    static let separator = dynamic(light: 0xE6ECF7, dark: 0x2B3460)
    static let accent = dynamic(light: 0x5266D8, dark: 0x8696FF)
    static let track = dynamic(light: 0xC9D6EC, dark: 0x39426E)
    static let good = dynamic(light: 0x21824C, dark: 0x5FD394)
    static let bad = dynamic(light: 0xC93D62, dark: 0xF6A3BC)  // the inner-ear pink, deepened for contrast
    /// A faint fill between card and background: inset fields, hovered rows, chips.
    static let wash = dynamic(light: 0xEEF3FC, dark: 0x262E55)
    /// The highlighted card (Snippets intro, License header) and the text on it:
    /// navy in light mode, a raised navy in dark mode rather than a white slab.
    static let feature = dynamic(light: 0x1E2140, dark: 0x2B3460)
    static let onFeature = dynamic(light: 0xFFFFFF, dark: 0xEEF1FF)

    private static func dynamic(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return rgb(isDark ? dark : light)
        }
    }

    private static func rgb(_ hex: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: 1)
    }
}

/// The palette for SwiftUI views. Only these colors are used in the window.
extension Color {
    static let fxBackground = Color(nsColor: Palette.background)
    static let fxCard = Color(nsColor: Palette.card)
    static let fxInk = Color(nsColor: Palette.ink)
    static let fxSecondary = Color(nsColor: Palette.secondary)
    static let fxSeparator = Color(nsColor: Palette.separator)
    static let fxAccent = Color(nsColor: Palette.accent)
    static let fxTrack = Color(nsColor: Palette.track)
    static let fxGood = Color(nsColor: Palette.good)
    static let fxBad = Color(nsColor: Palette.bad)
    static let fxWash = Color(nsColor: Palette.wash)
    static let fxFeature = Color(nsColor: Palette.feature)
    static let fxOnFeature = Color(nsColor: Palette.onFeature)
}
