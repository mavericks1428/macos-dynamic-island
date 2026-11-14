// swift-tools-version: 5.7
import PackageDescription

let package = Package(
    name: "AirIsland",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "AirIsland",
            targets: ["AirIsland"]
        )
    ],
    targets: [
        .executableTarget(
            name: "AirIsland",
            path: "Sources/AirIsland",
            linkerSettings: [
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("Carbon"),
                .linkedFramework("IOKit"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
