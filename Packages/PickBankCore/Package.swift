// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PickBankCore",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(
            name: "PickBankCore",
            targets: ["PickBankCore"]
        )
    ],
    targets: [
        .target(
            name: "PickBankCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "PickBankCoreTests",
            dependencies: ["PickBankCore"]
        )
    ]
)
