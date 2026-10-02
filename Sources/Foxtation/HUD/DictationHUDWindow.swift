import AppKit
import SwiftUI

/// Borderless, non-activating panel that hosts the pill. It never becomes key
/// or main, so the caret in the user's app keeps blinking.
final class DictationHUDWindow: NSPanel {

    init(model: HUDModel, flight: FoxFlight) {
        super.init(contentRect: NSRect(origin: .zero, size: HUDMetrics.windowSize),
                   styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                // drawn in SwiftUI so it follows the capsule
        // Fully transparent pixels pass clicks through, so the large flight
        // area around the pill never blocks the app underneath.
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        becomesKeyOnlyIfNeeded = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        // A dark HUD in both appearances keeps label contrast predictable.
        appearance = NSAppearance(named: .darkAqua)

        let host = NSHostingView(rootView: HUDStage(model: model, flight: flight))
        host.frame = NSRect(origin: .zero, size: HUDMetrics.windowSize)
        host.sizingOptions = []
        contentView = host
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Render once off screen so the first real show has no empty frame.
    func prewarm() {
        _ = HUDScreen.target()  // the first Accessibility lookup is the slow one
        _ = FoxFlight.images     // decode the pose bitmaps before the first flight
        alphaValue = 0
        orderFrontRegardless()
        contentView?.layoutSubtreeIfNeeded()
        contentView?.displayIfNeeded()
        orderOut(nil)
        alphaValue = 1
    }

    /// Moves the fixed-size window to its final spot. The frame is never
    /// animated; all motion happens inside the content.
    func place(_ placement: HUDPlacement) {
        guard let screen = HUDScreen.target() else { return }
        let origin = HUDScreen.windowOrigin(for: placement, on: screen)
        if frame.origin != origin { setFrameOrigin(origin) }
    }
}
