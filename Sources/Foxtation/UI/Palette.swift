import AppKit

/// Colors from the app icon: ice-blue tile, white fox, indigo waveform, navy ink.
enum Palette {
    static let background = dynamic(light: 0xDCE7F8, dark: 0x151A33)
    static let card = dynamic(light: 0xFFFFFF, dark: 0x1F2647)
    static let ink = dynamic(light: 0x1E2140, dark: 0xEEF1FF)
    static let secondary = dynamic(light: 0x5E6689, dark: 0x9AA3C9)
    static let separator = dynamic(light: 0xE6ECF7, dark: 0x2B3460)
    static let accent = dynamic(light: 0x5B6FE0, dark: 0x8696FF)
    static let track = dynamic(light: 0xC9D6EC, dark: 0x39426E)
    static let good = dynamic(light: 0x2E9E62, dark: 0x5FD394)
    static let bad = dynamic(light: 0xD8456B, dark: 0xF6A3BC)  // the inner-ear pink, deepened for contrast

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
