import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the pill. It never becomes key
/// or main, so the caret in the user's app keeps blinking.
final class DictationHUDWindow: NSPanel {

    init(model: HUDModel) {
        super.init(contentRect: NSRect(origin: .zero, size: HUDWindowMetrics.size),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                // drawn in SwiftUI so it follows the capsule
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // A dark HUD in both appearances keeps label contrast predictable.
        appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: HUDContent(model: model))
        host.frame = NSRect(origin: .zero, size: HUDWindowMetrics.size)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Render once off screen so the first real show has no empty frame.
    func prewarm() {
        _ = HUDScreen.target()  // the first Accessibility lookup is the slow one
        alphaValue = 0
        orderFrontRegardless()
        contentView?.layoutSubtreeIfNeeded()
        contentView?.displayIfNeeded()
        orderOut(nil)
        alphaValue = 1
    }

    /// Bottom center of the screen with the focused window.
    func place() {
        guard let screen = HUDScreen.target() else { return }
        let origin = HUDScreen.windowOrigin(on: screen)
        if frame.origin != origin { setFrameOrigin(origin) }
    }
}
