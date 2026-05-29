// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DeepSeekMonitor",
    defaultLocalization: "zh",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DeepSeekMonitor", targets: ["DeepSeekMonitor"])
    ],
    targets: [
        .executableTarget(
            name: "DeepSeekMonitor",
            path: ".",
            exclude: [
                "Resources",
                "DeepSeekMonitor.app",
                "build.sh",
                "CLAUDE.md",
                "README.md",
                "PRIVACY.md",
                "SECURITY.md",
                "LICENSE",
                ".gitignore",
                ".claude",
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("WebKit")
            ]
        )
    ]
)
