import AppKit
import ApplicationServices

/// The pill window: the pill plus room for its shadow.
enum HUDWindowMetrics {
    static let padding: CGFloat = 20
    static let size = CGSize(width: PillMetrics.width + padding * 2, height: PillMetrics.height + padding * 2)
}

enum HUDScreen {

    /// The screen holding the focused window, else the one under the mouse,
    /// else the main screen.
    static func target() -> NSScreen? {
        if let frame = focusedWindowFrame(),
           let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: frame.midX, y: frame.midY)) }) {
            return screen
        }
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) {
            return screen
        }
        return NSScreen.main
    }

    /// Window origin (Cocoa, bottom-left): centered, just above the Dock.
    static func windowOrigin(on screen: NSScreen) -> CGPoint {
        windowOrigin(visible: screen.visibleFrame)
    }

    static func windowOrigin(visible: CGRect) -> CGPoint {
        // visibleFrame already ends above the Dock.
        let pillBottom = visible.minY + 24
        return CGPoint(x: (visible.midX - HUDWindowMetrics.size.width / 2).rounded(),
                       y: (pillBottom - HUDWindowMetrics.padding).rounded())
    }

    /// Frame of the frontmost app's focused window in Cocoa coordinates.
    /// Needs Accessibility; returns nil without it.
    private static func focusedWindowFrame() -> CGRect? {
        guard AXIsProcessTrusted(), let app = NSWorkspace.shared.frontmostApplication else { return nil }
        let element = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(element, 0.1)

        var window: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXFocusedWindowAttribute as CFString, &window) == .success,
              let window else { return nil }
        let windowElement = window as! AXUIElement

        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)

        // AX uses a top-left origin anchored to the primary screen.
        guard let primary = NSScreen.screens.first else { return nil }
        return CGRect(x: position.x, y: primary.frame.maxY - position.y - size.height,
                      width: size.width, height: size.height)
    }
}
