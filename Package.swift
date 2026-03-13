// swift-tools-version:5.9
// This is a Swift Package Manager manifest for building ClaudeShell.
// For Xcode: open ClaudeShell.xcodeproj instead.
// For SPM-based builds (e.g., on CI), use this file.

import PackageDescription

let package = Package(
    name: "ClaudeShell",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .library(name: "ClaudeShellCore", targets: ["ClaudeShellCore"])
    ],
    targets: [
        // C shell engine
        .target(
            name: "CShellEngine",
            path: "ClaudeShell",
            sources: [
                "Shell/shell.c",
                "Shell/environment.c",
                "Commands/cmd_filesystem.c",
                "Commands/cmd_text.c",
                "Commands/cmd_network.c",
                "Commands/cmd_system.c"
            ],
            publicHeadersPath: "Shell",
            cSettings: [
                .headerSearchPath("Shell"),
                .headerSearchPath(".")
            ]
        ),
        // Swift layer
        .target(
            name: "ClaudeShellCore",
            dependencies: ["CShellEngine"],
            path: "ClaudeShell",
            sources: [
                "Bridge/ShellBridge.swift",
                "Claude/ClaudeEngine.swift",
                "Terminal/TerminalEmulator.swift",
                "App/ClaudeShellApp.swift",
                "App/TerminalView.swift",
                "App/SettingsView.swift"
            ]
        )
    ]
)
