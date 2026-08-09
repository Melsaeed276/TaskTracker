// swift-tools-version: 6.2
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppData",
    platforms: [.iOS(.v17), .macOS(.v14), .watchOS(.v10)],
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

