// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacMuleCore",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "MacMuleCore",
            targets: ["MacMuleCore"]
        ),
        .executable(
            name: "macmule-core-daemon",
            targets: ["MacMuleCoreDaemon"]
        )
    ],
    targets: [
        .target(
            name: "MacMuleZlib",
            linkerSettings: [
                .linkedLibrary("z")
            ]
        ),
        .target(
            name: "MacMuleCore",
            dependencies: ["MacMuleZlib"]
        ),
        .executableTarget(
            name: "MacMuleCoreDaemon",
            dependencies: ["MacMuleCore"]
        ),
        .testTarget(
            name: "MacMuleCoreTests",
            dependencies: ["MacMuleCore"]
        )
    ]
)
