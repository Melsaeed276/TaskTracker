// swift-tools-version: 6.2
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppFeature",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
    products: [.library(name: "AppFeature", targets: ["AppFeature"])],
    dependencies: [.package(path: "../TaskDomain"), .package(path: "../TimerDomain"), .package(path: "../AppData")],
    targets: [
        .target(
            name: "AppFeature",
            dependencies: ["TaskDomain", "TimerDomain", "AppData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppFeatureTests",
            dependencies: ["AppFeature", "AppData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
