// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LocalLrcPlayer",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "LocalLrcPlayer", targets: ["LocalLrcPlayer"])
    ],
    targets: [
        .target(
            name: "LocalLrcPlayer",
            path: "Sources/LocalLrcPlayer",
            exclude: ["main.swift"],
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        )
    ]
)
