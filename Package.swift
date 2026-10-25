// swift-tools-version: 6.3
// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0
// This is a Skip (https://skip.dev) package.
import PackageDescription

let needsAndroidMetadata = (Context.environment["SKIP_BRIDGE"] ?? "0") != "0"
    || (Context.environment["SKIP_DYNAMIC_LIBRARIES"] ?? "0") != "0"
let androidDependency: TargetDependencyCondition? = needsAndroidMetadata ? nil : .when(platforms: [.android])

let package = Package(
    name: "SwiftVideoComposition",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwiftVideo", type: needsAndroidMetadata ? .dynamic : nil, targets: ["SwiftVideo"]),
        .executable(name: "SwiftVideoExample", targets: ["SwiftVideoExample"]),
    ],
    dependencies: [
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.19"),
        .package(url: "https://github.com/skiptools/skip-fuse.git", from: "1.0.0"),
        .package(url: "https://github.com/skiptools/skip-foundation.git", from: "1.4.8"),
        .package(url: "https://github.com/skiptools/skip-bridge.git", from: "0.18.0"),
    ],
    targets: [
        .executableTarget(name: "SwiftVideoExample", dependencies: ["SwiftVideo"], path: "Examples/Milestone"),
        .target(name: "SwiftVideo", dependencies: [
            .product(name: "SkipFuse", package: "skip-fuse", condition: androidDependency),
            .target(name: "SwiftVideoMedia3", condition: androidDependency)
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "SwiftVideoMedia3", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation", condition: androidDependency),
            .product(name: "SkipBridge", package: "skip-bridge", condition: androidDependency)
        ], plugins: [.plugin(name: "skipstone", package: "skip")]),
        .target(name: "SwiftVideoTestSupport", dependencies: [
            .product(name: "SkipFoundation", package: "skip-foundation", condition: androidDependency),
            .product(name: "SkipBridge", package: "skip-bridge", condition: androidDependency)
        ], path: "Tests/SwiftVideoTestSupport", plugins: [.plugin(name: "skipstone", package: "skip")]),
        .testTarget(name: "SwiftVideoTests", dependencies: [
            "SwiftVideo",
            .target(name: "SwiftVideoTestSupport", condition: androidDependency),
            .product(name: "SkipTest", package: "skip")
        ], resources: [.process("Resources")], plugins: [.plugin(name: "skipstone", package: "skip")]),
    ],
    swiftLanguageModes: [.v6]
)
