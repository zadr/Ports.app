// swift-tools-version: 6.4
import PackageDescription

let library: [SwiftSetting] = [
    .swiftLanguageMode(.v6),
    .enableUpcomingFeature("ExistentialAny"),
    .enableUpcomingFeature("MemberImportVisibility"),
]

let application: [SwiftSetting] = library + [.defaultIsolation(MainActor.self)]

let package = Package(
    name: "Ports",
    platforms: [.macOS("27.0")],
    targets: [
        .target(name: "PortsShell", swiftSettings: library),
        .target(name: "PortsCLI", dependencies: ["PortsShell"], swiftSettings: library),
        .target(name: "PortsConfig", dependencies: ["PortsShell"], swiftSettings: library),
        .target(
            name: "PortsOverlay",
            dependencies: ["PortsShell", "PortsCLI", "PortsConfig"],
            swiftSettings: library
        ),
        .executableTarget(
            name: "Ports",
            dependencies: ["PortsShell", "PortsCLI", "PortsConfig", "PortsOverlay"],
            path: "Sources/Ports",
            exclude: ["Info.plist", "Resources"],
            swiftSettings: application
        ),
        .testTarget(name: "PortsCLITests", dependencies: ["PortsCLI"], swiftSettings: library),
        .testTarget(name: "PortsConfigTests", dependencies: ["PortsConfig"], swiftSettings: library),
        .testTarget(name: "PortsOverlayTests", dependencies: ["PortsOverlay"], swiftSettings: library),
    ]
)
