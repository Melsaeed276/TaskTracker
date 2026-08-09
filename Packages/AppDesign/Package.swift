// swift-tools-version: 6.0
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppDesign",
    platforms: [.iOS(.v18), .macOS(.v15), .watchOS(.v11)],
    products: [.library(name: "AppDesign", targets: ["AppDesign"])],
    dependencies: [],
    targets: [
        .target(
            name: "AppDesign",
            dependencies: [],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "AppDesignTests",
            dependencies: ["AppDesign"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
    ]
)
