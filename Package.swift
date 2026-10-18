// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SwiftyTerminal",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        // Colors, prompts, progress and formatted output. No system-library dependencies.
        .library(name: "SwiftyTerminal", targets: ["SwiftyTerminal"]),
        // libedit-backed line editing (history, tab completion) for REPL-style commands.
        .library(name: "SwiftyTerminalLineEditor", targets: ["SwiftyTerminalLineEditor"]),
        // `ScriptedTerminal`, a fake terminal for testing prompts and progress output.
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
        // A tour of every component; also what `Scripts/test-pty.py` drives in a real PTY.
        .executableTarget(name: "swifty-terminal-demo", dependencies: ["SwiftyTerminal", "SwiftyTerminalLineEditor"]),
        .testTarget(
            name: "SwiftyTerminalTests",
            dependencies: ["SwiftyTerminal", "SwiftyTerminalLineEditor", "SwiftyTerminalTesting"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
