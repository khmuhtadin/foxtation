import AppKit
import WebKit
// Renders an HTML page to a PNG at 2x: swift snap.swift page.html out.png WIDTH HEIGHT
// (the DMG background: see make-dmg.sh)
let args = CommandLine.arguments
let page = URL(fileURLWithPath: args[1]), out = URL(fileURLWithPath: args[2])
let width = Double(args[3])!, height = Double(args[4])!
final class Snapper: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            let config = WKSnapshotConfiguration()
            config.snapshotWidth = NSNumber(value: width)
            webView.takeSnapshot(with: config) { image, error in
                guard let image, let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
                      let png = rep.representation(using: .png, properties: [:]) else { print(error ?? "no image"); exit(1) }
                try! png.write(to: out); print("wrote", rep.pixelsWide, "x", rep.pixelsHigh); exit(0)
            }
        }
    }
}
let app = NSApplication.shared
let snapper = Snapper()
snapper.web.navigationDelegate = snapper
snapper.web.loadFileURL(page, allowingReadAccessTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
app.run()
