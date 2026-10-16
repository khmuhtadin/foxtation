import AppKit
import SwiftUI

// `#Preview` needs Xcode's PreviewsMacros plugin, which Command Line Tools
// don't ship, so previews use PreviewProvider. `--render-hud <dir>` writes the
// same frames to PNG for review without Xcode.

extension HUDModel {
    static let sampleLabels: [(HUDState, String)] = [
        (.listening, "Listening"),
        (.processing, "Cleaning up for"),
        (.success, "Pasted"),
        (.warning, "Daily limit reached"),
        (.error, "No speech detected"),
    ]

    /// The quieter text each sample shows after its label.
    static func sampleDetail(_ state: HUDState) -> String {
        switch state {
        case .processing: return "Slack"
        case .success: return "· 24 words"
        case .warning: return "· raw text pasted"
        default: return ""
        }
    }

    /// A shown pill in the given state.
    static func snapshot(_ state: HUDState, label: String) -> HUDModel {
        let model = HUDModel()
        model.isSnapshot = true
        model.state = state
        model.label = label
        model.detail = sampleDetail(state)
        model.actionTitle = state == .success ? "Undo" : nil
        model.listeningSince = state == .listening ? Date().addingTimeInterval(-7) : nil
        model.isShown = true
        model.waveformStarted = true
        model.meter.set(0.55)
        return model
    }
}

/// A 14" MacBook-sized screen with a Dock, with the pill where `HUDScreen` puts it.
struct HUDScreenMock: View {
    var model: HUDModel

    static let screen = CGSize(width: 1512, height: 982)
    static let menuBar: CGFloat = 37
    static let dock: CGFloat = 70

    var body: some View {
        let visible = CGRect(x: 0, y: Self.dock, width: Self.screen.width,
                             height: Self.screen.height - Self.menuBar - Self.dock)
        let origin = HUDScreen.windowOrigin(visible: visible)
        let top = Self.screen.height - origin.y - HUDWindowMetrics.size.height

        ZStack(alignment: .topLeading) {
            LinearGradient(colors: [Color(red: 0.32, green: 0.45, blue: 0.62), Color(red: 0.83, green: 0.72, blue: 0.62)],
                           startPoint: .top, endPoint: .bottom)
            Rectangle().fill(Color.black.opacity(0.25)).frame(height: Self.menuBar)
            RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.35))
                .frame(width: 560, height: 60)
                .offset(x: (Self.screen.width - 560) / 2, y: Self.screen.height - 66)
            HUDContent(model: model)
                .offset(x: origin.x, y: top)
        }
        .frame(width: Self.screen.width, height: Self.screen.height)
        .environment(\.colorScheme, .dark)
    }
}

#if DEBUG
struct HUDPreview_Previews: PreviewProvider {
    static var previews: some View {
        ForEach(HUDModel.sampleLabels, id: \.1) { state, label in
            HUDContent(model: .snapshot(state, label: label))
                .background(Color(white: 0.4))
                .previewDisplayName("State: \(label)")
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

        // Every visible state on a dark and a light wallpaper.
        let wallpaper = LinearGradient(colors: [Color(red: 0.09, green: 0.13, blue: 0.3), Color(red: 0.03, green: 0.05, blue: 0.14)],
                                       startPoint: .top, endPoint: .bottom)
        for (state, label) in HUDModel.sampleLabels {
            let model = HUDModel.snapshot(state, label: label)
            try write(HUDContent(model: model).background(wallpaper), "state-\(state)")
            try write(HUDContent(model: model).background(Color(white: 0.93)), "state-\(state)-light")
        }

        // Where it sits: bottom center, above the Dock.
        try write(HUDScreenMock(model: .snapshot(.listening, label: "Listening")), "placement", scale: 1)
    }
}
