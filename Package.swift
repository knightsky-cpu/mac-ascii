// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacAscii",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(name: "MacAscii", targets: ["MacAscii"]),
    ],
    targets: [
        .executableTarget(
            name: "MacAscii",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("CoreMedia"),
                .linkedFramework("CoreVideo"),
                .linkedFramework("Metal"),
                .linkedFramework("MetalKit"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
