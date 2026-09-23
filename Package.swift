// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Tero",
    platforms: [.iOS(.v15)],
    products: [
        .library(name: "Tero", targets: ["Tero"])
    ],
    targets: [
        .target(
            name: "Tero",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "TeroTests",
            dependencies: ["Tero"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
