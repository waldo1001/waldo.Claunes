// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "waldo.Claunes",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ClaunesCore", targets: ["ClaunesCore"]),
        .executable(name: "claunes", targets: ["claunes"]),
        .executable(name: "claune-launcher", targets: ["claune-launcher"]),
        .executable(name: "ClaunesApp", targets: ["ClaunesApp"]),
    ],
    targets: [
        // Core logic: profile store, bundle generation, migration, drift detection. No UI.
        .target(name: "ClaunesCore", path: "Sources/ClaunesCore"),
        // The tiny binary that lives inside every Claune bundle and execs Claude.
        .executableTarget(name: "claune-launcher", dependencies: ["ClaunesCore"], path: "Sources/claune-launcher"),
        // Command line interface, used for smoke tests and scripting.
        .executableTarget(name: "claunes", dependencies: ["ClaunesCore"], path: "Sources/claunes"),
        // SwiftUI app (main window + menu bar item).
        .executableTarget(name: "ClaunesApp", dependencies: ["ClaunesCore"], path: "Sources/ClaunesApp"),
        .testTarget(name: "ClaunesCoreTests", dependencies: ["ClaunesCore"], path: "Tests/ClaunesCoreTests"),
    ]
)
