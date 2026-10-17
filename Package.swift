// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "AgentMonitor",
    platforms: [.macOS("27.0")],
    products: [
        .library(name: "AgentMonitorCore", targets: ["AgentMonitorCore"]),
        .executable(name: "agent-monitor", targets: ["AgentMonitor"]),
        .executable(name: "agent-monitor-menubar", targets: ["AgentMonitorMenuBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", exact: "1.8.2"),
        .package(url: "https://github.com/SwiftTUI/swift-tui.git", exact: "0.14.0"),
    ],
    targets: [
        .executableTarget(
            name: "AgentMonitorMenuBar",
            dependencies: ["AgentMonitorCore", "AgentMonitorPresentation", "AgentMonitorActions"],
            resources: [.process("Resources")]),
        .testTarget(
            name: "AgentMonitorMenuBarTests", dependencies: ["AgentMonitorMenuBar"]),
        .target(name: "AgentMonitorCore"),
        .target(name: "AgentMonitorActions", dependencies: ["AgentMonitorCore"]),
        .testTarget(
            name: "AgentMonitorActionsTests", dependencies: ["AgentMonitorActions", "AgentMonitorCore"]),
        .target(
            name: "AgentMonitorPresentation", dependencies: ["AgentMonitorCore", "AgentMonitorActions"],
            resources: [.process("Resources")]),
        .target(
            name: "AgentMonitorTUI",
            dependencies: [
                "AgentMonitorCore", "AgentMonitorPresentation", "AgentMonitorActions",
                .product(name: "SwiftTUIRuntime", package: "swift-tui"),
                .product(name: "SwiftTUICLI", package: "swift-tui"),
            ]),
        .executableTarget(
            name: "AgentMonitor",
            dependencies: [
                "AgentMonitorCore", "AgentMonitorActions", "AgentMonitorPresentation", "AgentMonitorTUI",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]),
        .testTarget(name: "AgentMonitorCoreTests", dependencies: ["AgentMonitorCore"]),
        .executableTarget(
            name: "monitor-preview", dependencies: ["AgentMonitorCore", "AgentMonitorPresentation"],
            path: "Tools/Preview"),
        .testTarget(name: "PreviewTests", dependencies: ["monitor-preview"]),
        .executableTarget(
            name: "monitor-tui-fixture",
            dependencies: ["AgentMonitorCore", "AgentMonitorTUI", "AgentMonitorActions"],
            path: "Tests/Fixtures/TUIFixture"),
        .testTarget(
            name: "AgentMonitorTUITests",
            dependencies: [
                "monitor-tui-fixture",
                .product(name: "SwiftTUITestSupport", package: "swift-tui"),
            ]),
        .testTarget(
            name: "AgentMonitorCLITests",
            dependencies: [
                "AgentMonitor", .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "SwiftTUIViews", package: "swift-tui"),
            ]),
    ],
    swiftLanguageModes: [.v6]
)
