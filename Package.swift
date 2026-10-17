// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Foxtation",
    platforms: [.macOS(.v14)],
    dependencies: [
        // On-device Whisper on the Neural Engine.
        .package(url: "https://github.com/argmaxinc/WhisperKit", exact: "1.1.1"),
    ],
    targets: [
        .executableTarget(
            name: "Foxtation",
            dependencies: [.product(name: "WhisperKit", package: "WhisperKit")],
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
