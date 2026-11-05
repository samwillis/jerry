// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ExpeditionCore",
    products: [.library(name: "ExpeditionCore", targets: ["ExpeditionCore"])],
    targets: [
        .target(name: "ExpeditionCore"),
        .testTarget(name: "ExpeditionCoreTests", dependencies: ["ExpeditionCore"])
    ]
)
