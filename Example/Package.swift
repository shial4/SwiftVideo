// swift-tools-version: 6.3
// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0
// This is a Skip (https://skip.dev) package.
import PackageDescription

let needsAndroidMetadata = (Context.environment["SKIP_DYNAMIC_LIBRARIES"] ?? "0") != "0"
    || (Context.environment["SKIP_BRIDGE"] ?? "0") != "0"
let androidOnly: TargetDependencyCondition? = needsAndroidMetadata ? nil : .when(platforms: [.android])

let package = Package(
    name: "Example",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "SwiftVideoEditor", type: .dynamic, targets: ["SwiftVideoEditor"]),
        .executable(name: "VideoEditorDemo", targets: ["EditorLauncher"]),
    ],
    dependencies: [
        .package(name: "SwiftVideo", path: ".."),
        .package(url: "https://github.com/skiptools/skip.git", from: "1.9.19"),
        .package(url: "https://github.com/skiptools/skip-fuse-ui.git", from: "1.9.1"),
        .package(url: "https://github.com/skiptools/skip-av.git", from: "0.7.2"),
    ],
    targets: [
        .target(name: "SwiftVideoEditor", dependencies: [
            .product(name: "SwiftVideo", package: "SwiftVideo"),
            .product(name: "SkipFuseUI", package: "skip-fuse-ui", condition: androidOnly),
            .product(name: "SkipAV", package: "skip-av", condition: androidOnly)
        ], resources: [.process("Resources")],
           linkerSettings: [.linkedFramework("AVKit", .when(platforms: [.macOS]))],
           plugins: [.plugin(name: "skipstone", package: "skip")]),
        .executableTarget(name: "EditorLauncher", dependencies: ["SwiftVideoEditor"], path: "Launcher"),
        .testTarget(name: "SwiftVideoEditorTests", dependencies: ["SwiftVideoEditor"]),
    ],
    swiftLanguageModes: [.v6]
)
