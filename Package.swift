// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Tappi",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Tappi",
            path: "Sources/Tappi",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("QuartzCore"),
            ]
        )
    ]
)
