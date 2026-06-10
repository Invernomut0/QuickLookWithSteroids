// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OmniPreviewCore",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "OmniPreviewCore", targets: ["OmniPreviewCore"]),
        .library(name: "OmniPreviewUI", targets: ["OmniPreviewUI"]),
    ],
    targets: [
        .target(name: "OmniPreviewCore"),
        .target(name: "OmniPreviewUI", dependencies: ["OmniPreviewCore"]),
        .testTarget(name: "OmniPreviewCoreTests", dependencies: ["OmniPreviewCore"]),
    ]
)
