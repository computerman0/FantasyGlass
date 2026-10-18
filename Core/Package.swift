// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FantasyCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "FantasyCore", targets: ["FantasyCore"])],
    targets: [
        .target(name: "FantasyCore"),
        .testTarget(name: "FantasyCoreTests", dependencies: ["FantasyCore"], resources: [.copy("Fixtures")])
    ]
)
