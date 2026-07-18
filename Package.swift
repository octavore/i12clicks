// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "InternationalClicks",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "InternationalClicks",
            path: "Sources/InternationalClicks",
            resources: [.copy("Resources/clickhouse.svg")]
        ),
    ]
)
