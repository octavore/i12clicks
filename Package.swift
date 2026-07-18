// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClickHouseApp",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClickHouseApp",
            path: "Sources/ClickHouseApp",
            resources: [.copy("Resources/clickhouse.svg")]
        ),
    ]
)
