import AppKit
import SwiftUI

/// `Foxtation --render-window <dir> [filter]` writes a PNG of every screen with
/// sample data, light and dark, for comparing against docs/design/boards.
/// `filter` keeps only shots whose name contains it (e.g. "insights").
enum WindowSnapshots {

    static let size = NSSize(width: 1280, height: 820)

    @MainActor
    static func render(to directory: URL, filter: String?) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var shots: [(String, (AppModel) -> Void)] = [
            ("home", { $0.page = .home }),
            ("history", { $0.page = .history }),
            ("insights", { $0.page = .insights }),
            ("dictionary", { $0.page = .dictionary }),
            ("snippets", { $0.page = .snippets }),
            ("style", { $0.page = .style }),
        ]
        for section in SettingsSection.allCases {
            shots.append(("settings-\(section.rawValue)", { $0.page = .home; $0.settingsSection = section }))
        }

        for (name, setUp) in shots where filter.map({ name.contains($0) }) ?? true {
            for dark in [false, true] {
                let model = AppModel.sample()
                setUp(model)
                let file = directory.appendingPathComponent("\(name)\(dark ? "-dark" : "").png")
                try write(RootView(model: model), dark: dark, to: file)
                print("wrote \(file.lastPathComponent)")
            }
        }
    }

    /// Renders through a real (off-screen) window so AppKit-backed controls
    /// such as switches and pop-ups draw too, which ImageRenderer can't do.
    @MainActor
    static func write<V: View>(_ view: V, dark: Bool, to file: URL) throws {
        let window = NSWindow(contentRect: NSRect(origin: NSPoint(x: -4000, y: -4000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        window.contentView = host
        window.orderFrontRegardless()
        // Let SwiftUI lay out and draw a couple of passes.
        for _ in 0..<3 { RunLoop.current.run(until: Date().addingTimeInterval(0.15)) }
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { throw CocoaError(.fileWriteUnknown) }
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        guard let data = rep.representation(using: .png, properties: [:]) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: file)
    }
}
