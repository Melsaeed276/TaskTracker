// swift-tools-version: 6.2
import PackageDescription

// Dependency rules are enforced here, by the compiler. See docs/ARCHITECTURE.md §8.
let package = Package(
    name: "AppDesign",
    platforms: [.iOS(.v26), .macOS(.v26), .watchOS(.v26)],
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
