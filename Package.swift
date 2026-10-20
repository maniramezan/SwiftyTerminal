// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftyTerminal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "SwiftyTerminal", targets: ["SwiftyTerminal"]),
        .library(name: "SwiftyTerminalLineEditor", targets: ["SwiftyTerminalLineEditor"]),
        .library(name: "SwiftyTerminalTesting", targets: ["SwiftyTerminalTesting"]),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-docc-plugin", from: "1.5.0")
    ],
    targets: [
        .target(name: "CSwiftyTerminal"),
        .target(name: "SwiftyTerminal", dependencies: ["CSwiftyTerminal"]),
        .target(
            name: "CSwiftyTerminalLineEditor",
            linkerSettings: [.linkedLibrary("edit", .when(platforms: [.macOS]))]
        ),
        .target(
            name: "SwiftyTerminalLineEditor",
            dependencies: ["CSwiftyTerminalLineEditor"]
        ),
        .target(name: "SwiftyTerminalTesting", dependencies: ["SwiftyTerminal"]),
        .executableTarget(
            name: "swifty-terminal-demo",
            dependencies: ["SwiftyTerminal", "SwiftyTerminalLineEditor"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .executableTarget(
            name: "swifty-terminal-release-check",
            dependencies: ["SwiftyTerminal", "SwiftyTerminalTesting"],
            swiftSettings: [.defaultIsolation(MainActor.self)]
        ),
        .testTarget(
            name: "SwiftyTerminalTests",
            dependencies: ["SwiftyTerminal", "SwiftyTerminalLineEditor", "SwiftyTerminalTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
