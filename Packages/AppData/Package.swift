// swift-tools-version: 6.0
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppData",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "AppData", targets: ["AppData"])],
    dependencies: [.package(path: "../TaskDomain"), .package(path: "../TimerDomain")],
    targets: [
        .target(
            name: "AppData",
            dependencies: ["TaskDomain", "TimerDomain"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppDataTests",
            dependencies: ["AppData"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
