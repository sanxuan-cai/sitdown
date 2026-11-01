// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SitStandAssistant",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "SitStandAssistant", targets: ["SitStandAssistant"])],
    targets: [
        .executableTarget(name: "SitStandAssistant"),
        .testTarget(name: "SitStandAssistantTests", dependencies: ["SitStandAssistant"])
    ]
)
