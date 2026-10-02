// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Foxtation",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Foxtation",
            path: "Sources/Foxtation",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Carbon"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
