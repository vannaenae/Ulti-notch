// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UltiNotchKit",
    platforms: [.macOS("14.6")],
    products: [
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .library(name: "NotchModuleKit", targets: ["NotchModuleKit"]),
    ],
    targets: [
        // Pure Swift. Foundation only. No AppKit, no SwiftUI, no system frameworks.
        // Holds every contract and every piece of logic that can be unit tested.
        .target(name: "NotchCore"),

        // SwiftUI-facing half of the module protocol. Modules depend on this, never on the app.
        .target(name: "NotchModuleKit", dependencies: ["NotchCore"]),

        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
    ]
)
