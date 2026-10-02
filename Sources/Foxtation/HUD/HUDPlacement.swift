import AppKit
import ApplicationServices

/// Where the dictation pill sits on screen.
enum HUDPlacement: String, CaseIterable {
    case rightEdge, leftEdge, topCenter, bottomCenter

    var label: String {
        switch self {
        case .rightEdge: return "Top right"
        case .leftEdge:  return "Top left"
        case .topCenter: return "Top center"
        case .bottomCenter: return "Bottom center"
        }
    }
}

/// Fixed geometry shared by the window, the pill view and the fox flight.
enum HUDMetrics {
    static let pillSize = CGSize(width: 320, height: 52)
    /// Room around the pill for the fox's flight, taken from the path's own bounds.
    static let margins = FoxFlight.margins
    static let windowSize = CGSize(width: margins.left + pillSize.width + margins.right,
                                   height: margins.top + pillSize.height + margins.bottom)
    static let pillRect = CGRect(origin: CGPoint(x: margins.left, y: margins.top), size: pillSize)

    static let foxSlotSize = PillMetrics.faceSize

    /// Center of the seated face, relative to the pill's center.
    static let foxSlotOffset = CGPoint(x: PillMetrics.faceCenterX - pillSize.width / 2, y: 0)

    /// Center of the seated face in window (SwiftUI, top-left origin) coordinates.
    static var foxSlotCenter: CGPoint {
        CGPoint(x: pillRect.midX + foxSlotOffset.x, y: pillRect.midY)
    }
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

    /// Window origin (Cocoa, bottom-left) for the given placement.
    static func windowOrigin(for placement: HUDPlacement, on screen: NSScreen) -> CGPoint {
        windowOrigin(for: placement, visible: screen.visibleFrame, frame: screen.frame,
                     safeTop: screen.safeAreaInsets.top)
    }

    static func windowOrigin(for placement: HUDPlacement, visible: CGRect, frame: CGRect, safeTop: CGFloat) -> CGPoint {
        let pill = HUDMetrics.pillSize
        let pillRect = HUDMetrics.pillRect

        // visibleFrame already sits below the menu bar; when the menu bar
        // auto-hides it does not, so clamp to the notch safe area as well.
        let top = min(visible.maxY, frame.maxY - safeTop)

        let pillTop: CGFloat
        let pillX: CGFloat
        switch placement {
        case .rightEdge:
            pillTop = top - 20
            pillX = visible.maxX - 20 - pill.width
        case .leftEdge:
            pillTop = top - 20
            pillX = visible.minX + 20
        case .topCenter:
            pillTop = top - 16
            pillX = visible.midX - pill.width / 2
        case .bottomCenter:
            // visibleFrame already ends above the Dock.
            pillTop = visible.minY + 24 + pill.height
            pillX = visible.midX - pill.width / 2
        }
        // The window extends past the pill by the flight margins; parts that
        // fall off screen are simply not drawn.
        return CGPoint(x: (pillX - pillRect.minX).rounded(),
                       y: (pillTop + pillRect.minY - HUDMetrics.windowSize.height).rounded())
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
