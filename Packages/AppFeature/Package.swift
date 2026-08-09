// swift-tools-version: 6.0
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppFeature",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
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
            dependencies: ["AppFeature"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
