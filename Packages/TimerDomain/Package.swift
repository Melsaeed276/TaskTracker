// swift-tools-version: 6.0
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "TimerDomain",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "TimerDomain", targets: ["TimerDomain"])],
    dependencies: [],
    targets: [
        .target(
            name: "TimerDomain",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TimerDomainTests",
            dependencies: ["TimerDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
