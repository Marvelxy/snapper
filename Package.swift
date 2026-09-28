// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Snapper",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "Snapper",
            path: "Sources/Snapper",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
