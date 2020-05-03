// swift-tools-version:5.2

import PackageDescription

let package = Package(
    name: "Fluxor",
    platforms: [
        .macOS(.v10_15),
        .iOS(.v13),
        .tvOS(.v13),
    ],
    products: [
        .library(
            name: "Fluxor",
            targets: ["Fluxor"]),
        .library(
            name: "FluxorTestSupport",
            targets: ["FluxorTestSupport"]),
    ],
    targets: [
        .target(
            name: "AnyCodable"),
        .testTarget(
            name: "AnyCodableTests",
            dependencies: ["AnyCodable"]),
        .target(
            name: "Fluxor",
            dependencies: ["AnyCodable"]),
        .testTarget(
            name: "FluxorTests",
            dependencies: ["Fluxor"]),
        .target(
            name: "FluxorTestSupport",
            dependencies: ["Fluxor"]),
    ]
)
