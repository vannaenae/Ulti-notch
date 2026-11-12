// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UltiNotchKit",
    platforms: [.macOS("14.6")],
    products: [
        .library(name: "NotchCore", targets: ["NotchCore"]),
        .library(name: "NotchModuleKit", targets: ["NotchModuleKit"]),
        .library(name: "Services", targets: ["Services"]),
        .library(name: "Modules", targets: ["Modules"]),
        .library(name: "NotchShell", targets: ["NotchShell"]),
    ],
    targets: [
        // Pure Swift, Foundation only. Every contract and all testable logic.
        .target(name: "NotchCore"),
        // SwiftUI half of the module protocol.
        .target(name: "NotchModuleKit", dependencies: ["NotchCore"]),
        // The only code that talks to system APIs.
        .target(name: "Services", dependencies: ["NotchCore"]),
        // First-party modules. Depend on NotchModuleKit + Services, never on the shell.
        .target(name: "Modules", dependencies: ["NotchModuleKit", "Services"]),
        // Windows, displays, input, island rendering.
        .target(name: "NotchShell", dependencies: ["NotchModuleKit"]),

        .testTarget(name: "NotchCoreTests", dependencies: ["NotchCore"]),
        .testTarget(name: "ServicesTests", dependencies: ["Services"]),
        .testTarget(name: "ModulesTests", dependencies: ["Modules"]),
    ]
)
