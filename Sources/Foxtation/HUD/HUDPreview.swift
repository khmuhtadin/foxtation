import AppKit
import SwiftUI

// `#Preview` needs Xcode's PreviewsMacros plugin, which Command Line Tools
// don't ship, so previews use PreviewProvider. `--render-hud <dir>` writes the
// same frames to PNG for review without Xcode.

extension VectorFoxAnimator {
    /// Sets a state with no cross-fade or one-shot in flight.
    func settle(_ state: FoxState) {
        setState(state)
        jumpToSettled()
    }
}

extension HUDModel {
    static let sampleLabels: [(HUDState, String)] = [
        (.listening, "Listening…"),
        (.processing, "Transcribing…"),
        (.success, "Pasted"),
        (.error, "No speech detected"),
    ]

    /// A seated pill in the given state.
    static func snapshot(_ state: HUDState, label: String, placement: HUDPlacement = .rightEdge) -> HUDModel {
        let model = HUDModel()
        model.isSnapshot = true
        model.placement = placement
        model.state = state
        model.label = label
        model.pillOpacity = 1
        model.contentOpacity = 1
        model.slotOpacity = 1
        model.slotScale = 1
        model.waveformStarted = true
        model.meter.set(0.55)
        model.fox.setAmplitude(0.4)
        model.fox.settle(state.foxState)
        return model
    }

    /// A frame from the middle of the entry flight, `time` seconds in.
    static func flightFrame(_ time: Double, placement: HUDPlacement) -> (HUDModel, FoxFlight) {
        let model = snapshot(.listening, label: "Listening…", placement: placement)
        model.contentOpacity = FoxFlight.ramp(time, FoxFlight.landingReal + 0.06, FoxFlight.landingReal + 0.28)
        model.slotOpacity = FoxFlight.ramp(time, FoxFlight.landingReal, FoxFlight.landingReal + 0.15)
        let flight = FoxFlight()
        flight.freeze(at: time, mirrored: placement == .rightEdge)
        return (model, flight)
    }
}

/// A 14" MacBook-sized screen with menu bar and notch, with the HUD window
/// placed where `HUDScreen` would put it.
struct HUDPlacementMock: View {
    var placement: HUDPlacement
    var menuBarHidden = false
    var model: HUDModel

    static let screen = CGSize(width: 1512, height: 982)
    static let menuBar: CGFloat = 37

    var body: some View {
        let frame = CGRect(origin: .zero, size: Self.screen)
        let visible = menuBarHidden ? frame
            : CGRect(x: 0, y: 0, width: frame.width, height: frame.height - Self.menuBar)
        let origin = HUDScreen.windowOrigin(for: placement, visible: visible, frame: frame, safeTop: Self.menuBar)
        let top = frame.height - origin.y - HUDMetrics.windowSize.height

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.45, blue: 0.62), Color(red: 0.83, green: 0.72, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            if !menuBarHidden {
                Rectangle().fill(Color.black.opacity(0.25)).frame(height: Self.menuBar)
            }
            Rectangle().fill(Color.black)
                .frame(width: 190, height: 32)
                .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 10, bottomTrailingRadius: 10))
                .offset(x: (Self.screen.width - 190) / 2)
            HUDStage(model: model, flight: FoxFlight())
                .offset(x: origin.x, y: top)
        }
        .frame(width: Self.screen.width, height: Self.screen.height)
        .environment(\.colorScheme, .dark)
    }
}

#if DEBUG
struct HUDPreview_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ForEach(HUDModel.sampleLabels, id: \.1) { state, label in
                HUDStage(model: .snapshot(state, label: label), flight: FoxFlight())
                    .background(Color(white: 0.4))
                    .previewDisplayName("State: \(label)")
            }
            ForEach(HUDPlacement.allCases, id: \.self) { placement in
                HUDPlacementMock(placement: placement, model: .snapshot(.listening, label: "Listening…", placement: placement))
                    .scaleEffect(0.5)
                    .previewDisplayName("Placement: \(placement.label)")
            }
        }
    }
}
#endif

// MARK: - PNG export

enum HUDSnapshots {

    @MainActor
    static func render(to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        func write<V: View>(_ view: V, _ name: String, scale: CGFloat = 2) throws {
            let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
            renderer.scale = scale
            guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
            let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
            try data.write(to: directory.appendingPathComponent(name + ".png"))
            print("wrote \(name).png")
        }

        // A dark wallpaper like the storyboard's.
        let wallpaper = LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.3), Color(red: 0.03, green: 0.05, blue: 0.14)],
                                       startPoint: .top, endPoint: .bottom)

        // Every visible state, seated. `hidden` and `cancelled` draw nothing.
        for (state, label) in HUDModel.sampleLabels {
            let model = HUDModel.snapshot(state, label: label)
            try write(HUDStage(model: model, flight: FoxFlight()).background(wallpaper), "state-\(state)")
            try write(HUDStage(model: model, flight: FoxFlight()).background(Color(white: 0.93)), "state-\(state)-light")
            if state == .listening, let slot = model.measuredSlotCenter {
                let end = FoxFlight.landingPoint
                print(String(format: "handoff delta %.3fpt (flight %.1f,%.1f slot %.1f,%.1f)",
                             hypot(end.x - slot.x, end.y - slot.y), end.x, end.y, slot.x, slot.y))
                model.checkHandoff()
            }
        }

        // The entry flight, frame by frame (storyboard scenes 1–8); mirrored for the right edge.
        let times = [0.1, 0.2, 0.25, 0.3, 0.35, 0.45, 0.55, 0.65, 0.85, 1.1, 1.4, 1.75, 2.05, 2.35]
        for (placement, prefix) in [(HUDPlacement.topCenter, "flight"), (.rightEdge, "flight-mirrored")] {
            for (index, time) in times.enumerated() {
                let (model, flight) = HUDModel.flightFrame(time, placement: placement)
                try write(HUDStage(model: model, flight: flight).background(wallpaper),
                          String(format: "%@-%02d", prefix, index + 1))
            }
        }

        // Where each placement lands on a notched screen.
        for placement in HUDPlacement.allCases {
            let model = HUDModel.snapshot(.listening, label: "Listening…", placement: placement)
            try write(HUDPlacementMock(placement: placement, model: model), "placement-\(placement)", scale: 1)
        }
        let hidden = HUDModel.snapshot(.listening, label: "Listening…", placement: .topCenter)
        try write(HUDPlacementMock(placement: .topCenter, menuBarHidden: true, model: hidden),
                  "placement-topCenter-menubar-autohide", scale: 1)
    }
}
