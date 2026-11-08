// swift-tools-version: 6.0
import PackageDescription

/// BrewbutlerCore is the testable, UI-free part of the app. The Xcode target compiles
/// the same sources from `Brewbutler/Core`; this package exists so `swift test` can run
/// parser / process / model tests without an Xcode test target.
let package = Package(
    name: "BrewbutlerCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BrewbutlerCore", targets: ["BrewbutlerCore"])
    ],
    targets: [
        .target(
            name: "BrewbutlerCore",
            path: "Brewbutler/Core"
        ),
        .testTarget(
            name: "BrewbutlerCoreTests",
            dependencies: ["BrewbutlerCore"],
            path: "Tests/BrewbutlerCoreTests"
        )
    ],
    swiftLanguageModes: [.v5]
)
