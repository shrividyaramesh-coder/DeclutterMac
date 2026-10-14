// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TidyMac",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "TidyMacCore",
            targets: ["TidyMacCore"]
        ),
        .executable(
            name: "TidyMacApp",
            targets: ["TidyMacApp"]
        ),
        .executable(
            name: "TidyMacTestRunner",
            targets: ["TidyMacTestRunner"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "TidyMacCore",
            dependencies: [],
            path: "Sources/TidyMacCore",
            resources: [
                .process("Resources")
            ]
        ),
        .executableTarget(
            name: "TidyMacApp",
            dependencies: [
                "TidyMacCore"
            ],
            path: "Sources/TidyMacApp"
        ),
        .executableTarget(
            name: "TidyMacTestRunner",
            dependencies: [
                "TidyMacCore"
            ],
            path: "Tests/TidyMacTestRunner"
        )
    ]
)
