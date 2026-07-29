// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WriteSense",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WriteSense", targets: ["WriteSense"])
    ],
    targets: [
        .executableTarget(
            name: "WriteSense",
            path: "Sources/WriteSense",
            linkerSettings: [
                .linkedFramework("Security")
            ]
        ),
        .testTarget(
            name: "WriteSenseTests",
            dependencies: ["WriteSense"],
            path: "Tests/WriteSenseTests"
        )
    ]
)
