// swift-tools-version: 6.0
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "TaskDomain",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "TaskDomain", targets: ["TaskDomain"])],
    dependencies: [],
    targets: [
        .target(
            name: "TaskDomain",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "TaskDomainTests",
            dependencies: ["TaskDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
