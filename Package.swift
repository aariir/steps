// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Steps",
    platforms: [.macOS("26.0")],
    targets: [
        .target(name: "StepsCore", path: "Sources/StepsCore", swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(
            name: "Steps",
            dependencies: ["StepsCore"],
            path: "Sources/Steps",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "CoreChecks",
            dependencies: ["StepsCore"],
            path: "Sources/CoreChecks",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
