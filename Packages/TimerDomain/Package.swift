// swift-tools-version: 6.2
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "TimerDomain",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
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
