// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerminautApp",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TerminautApp", targets: ["TerminautApp"]),
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "TerminautApp",
            dependencies: [],
            path: "Sources",
            resources: []
        ),
        .testTarget(
            name: "TerminautAppTests",
            dependencies: ["TerminautApp"],
            path: "Tests"
        )
    ]
)
