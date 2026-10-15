// swift-tools-version: 5.9
// Package.swift — Scandium: SoundCloud Client for iOS 15.0+
// Author: MeoHunter | License: GPL-3.0

import PackageDescription

let package = Package(
    name: "Scandium",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "Scandium",
            targets: ["Scandium"]
        )
    ],
    targets: [
        .target(
            name: "Scandium",
            path: "Sources/Scandium",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "ScandiumTests",
            dependencies: ["Scandium"],
            path: "Tests/ScandiumTests"
        )
    ]
)
