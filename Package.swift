// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickBank",
    defaultLocalization: "zh-Hans",
    platforms: [
        .iOS(.v18),
        .macOS(.v15),
    ],
    products: [
        .library(
            name: "PickBankCore",
            targets: ["PickBankCore"]
        ),
        .library(
            name: "PickBankUI",
            targets: ["PickBankUI"]
        ),
        .executable(
            name: "PickBankPreviewApp",
            targets: ["PickBankPreviewApp"]
        ),
    ],
    targets: [
        .target(
            name: "PickBankCore",
            path: "Sources/PickBankCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .target(
            name: "PickBankUI",
            dependencies: ["PickBankCore"],
            path: "Sources/PickBankUI",
            resources: [
                .copy("Resources/PetAssets"),
            ]
        ),
        .executableTarget(
            name: "PickBankPreviewApp",
            dependencies: ["PickBankCore", "PickBankUI"],
            path: "Sources/PickBankPreviewApp"
        ),
        .testTarget(
            name: "PickBankCoreTests",
            dependencies: ["PickBankCore", "PickBankUI"],
            path: "Tests/PickBankCoreTests"
        ),
    ]
)
