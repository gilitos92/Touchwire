// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Touchwire",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Touchwire",
            path: "Sources/Touchwire",
            // C callbacks (event tap, IOKit, display reconfiguration) all land on the main run loop.
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("AppKit")]
        )
    ]
)
