<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo

**Compose video. Stay in Swift.**

A declarative video composition library for **iOS, macOS, and Android**. Turn footage, images, text, and audio into finished videos with a SwiftUI-style DSL, precise timeline editing, and GPU-backed rendering.

[![Release](https://img.shields.io/github/v/release/shial4/SwiftVideo)](https://github.com/shial4/SwiftVideo/releases)
[![Swift 6.3+](https://img.shields.io/badge/Swift-6.3%2B-F05138?logo=swift&logoColor=white)](Package.swift)
[![Apple tests](https://github.com/shial4/SwiftVideo/actions/workflows/apple.yml/badge.svg)](https://github.com/shial4/SwiftVideo/actions/workflows/apple.yml)
[![Android tests](https://github.com/shial4/SwiftVideo/actions/workflows/android.yml/badge.svg)](https://github.com/shial4/SwiftVideo/actions/workflows/android.yml)
[![Documentation](https://img.shields.io/badge/Documentation-Read%20the%20docs-blue)](Documentation/README.md)
[![Apache 2.0](https://img.shields.io/badge/License-Apache%202.0-blue)](LICENSE)

[Quick start](#quick-start) | [Install](#install) | [iOS](#native-ios-and-macos) | [Skip](#skip-for-ios-and-android) | [Kotlin](#native-android-and-kotlin) | [API reference](Documentation/APIReference.md)

![SwiftVideo Studio: preview, timeline editing, text overlays, filters, and export](Documentation/Images/editor.gif)

Built with SwiftVideo: [run the example editor on iOS or Android](Example/README.md), or [view the exported composition](Documentation/Images/composition.gif).

## Why SwiftVideo?

- **A timeline that reads like your UI.** Compose tracks and clips with builders, modifiers, conditionals, and loops. Keep immutable project values in SwiftUI state or your own model.
- **One Swift composition, three platforms.** Use the same API with AVFoundation on Apple and Media3 through Skip Fuse on Android.
- **GPU-backed visuals.** Metal-backed Core Image and Media3's OpenGL pipeline handle transforms, filters, and compositing. Text is prepared once for each export.
- **Editing with predictable results.** Rational time, atomic edit batches, and split/trim operations preserve source offsets and effect timing.
- **Export with control.** Async/await, progress, cancellation, and destination protection are built in. Projects are Codable, Hashable, and Sendable.

## Quick start

Add a title to five seconds of footage and export an MP4:

```swift
import Foundation
import SwiftVideo

func exportTitle(inputURL: URL, to outputURL: URL) async throws {
    let duration = try VideoTime(value: 5, timescale: 1)
    let project = VideoProject {
        MediaTrack("Footage") {
            MediaClip.video(inputURL, duration: duration)
        }
        MediaTrack("Title") {
            MediaClip.text("Your story", duration: duration,
                           style: TextStyle(fontSize: 96))
                .zIndex(1)
                .transform(VisualTransform(y: 0.8, width: 0.9, height: 0.15))
        }
    }

    let exporter = VideoExporter()
    try await exporter.export(project, to: outputURL,
                              settings: ExportSettings(resolution: .hd1080))
}
```

Supply a readable local video with at least five seconds of footage and an unused output URL ending in `.mp4`. Call the function from an async context, such as a SwiftUI task or a UIKit action's `Task`. See [progress and cancellation](Documentation/Recipes.md#cancellable-export-from-swiftui), or build an [image and text title scene](Documentation/Recipes.md#image-and-text-title-scene) and [commentary video with timed captions](Documentation/Recipes.md#commentary-video-and-timed-captions).

## Install

SwiftVideo is distributed through **Swift Package Manager**. Add the repository dependency and the **`SwiftVideo`** product to the target that uses it:

```swift
// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "MyVideoFeature",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "MyVideoFeature", targets: ["MyVideoFeature"])
    ],
    dependencies: [
        .package(url: "https://github.com/shial4/SwiftVideo.git", from: "0.0.1")
    ],
    targets: [
        .target(name: "MyVideoFeature", dependencies: [
            .product(name: "SwiftVideo", package: "SwiftVideo")
        ])
    ]
)
```

Then `import SwiftVideo`. For an existing package, merge these dependency entries into its manifest. Android applications also need the Skip setup below.

| Your project | Requirements | Integration |
| --- | --- | --- |
| Native iOS / iPadOS | iOS 17+, Swift 6.3+ | SwiftPM or Xcode; SwiftUI and UIKit supported |
| Native macOS | macOS 14+, Swift 6.3+ | SwiftPM or Xcode; SwiftUI and AppKit supported |
| Shared iOS + Android | Apple requirements above; Android API 28+ | Skip Fuse with a matching Swift Android SDK |
| Native Android / Kotlin | API 28+, Skip build toolchain for the adapter | Generated Kotlin bridge and packaged native libraries |

### Native iOS and macOS

1. In Xcode, choose **File > Add Package Dependencies** and enter `https://github.com/shial4/SwiftVideo.git`.
2. Select **Up to Next Major Version**, starting at **0.0.1**, and add the **SwiftVideo** product to your app target.
3. Add `import SwiftVideo` and use the [quick start](#quick-start) from your SwiftUI, UIKit, or AppKit code.

Use Xcode's Swift toolchain for Apple builds. You do not need an Android SDK, JDK, or emulator to use the Apple renderer. Your app owns media selection, file permissions, playback, and sharing. [Native app integration](Documentation/Integration.md#native-ios-and-macos).

### Skip for iOS and Android

Add the same SwiftPM dependency to your **Skip Fuse app's shared `Package.swift`** and link `SwiftVideo` to its native Swift target. Keep that target's `Sources/<Target>/Skip/skip.yml` in native mode:

```yaml
skip:
  mode: 'native'
```

Use `import SwiftVideo` and the same composition code on both platforms. Keep your generated Skip app launcher and build integration: Android rendering needs the initialized application context, the generated Media3 JVM module, and the native Swift libraries.

Start with the [working iOS + Android example](Example/README.md), or follow the [Skip integration guide](Documentation/Integration.md#skip-for-ios-and-android). Skip Lite callers need a bridged native wrapper; the SwiftVideo DSL is not directly transpiled to Kotlin.

### Native Android and Kotlin

**Version 0.0.1 ships a Swift package, not a Maven artifact or a directly callable Kotlin DSL.** You can use it behind a small Skip Fuse wrapper while keeping your Android UI in Kotlin or Compose:

1. Create a native Skip framework that depends on SwiftVideo.
2. Expose a small Swift API using bridge-friendly inputs such as file paths, text, and durations. Enable Skip's `kotlincompat` bridging for that wrapper.
3. Export the generated Android libraries with `skip export` and integrate their dependencies and native libraries into your Gradle app.
4. Initialize the Skip application context, then call the generated API from a Kotlin coroutine.

The [Kotlin integration walkthrough](Documentation/Integration.md#native-android-and-kotlin) includes a Swift export wrapper, a Kotlin call, and packaging guidance. The composition and rendering implementation stays in this library.

## What you can build

| Feature | Included |
| --- | --- |
| Title scenes and captions | Image overlays, timed text, font/color/alignment/shadow, custom font files |
| Commentary and picture-in-picture | Overlapping video tracks, crop, fit/fill/stretch, position, rotation, opacity |
| Animation and effects | Keyframes with easing; brightness, contrast, saturation, blur, and sepia |
| Timeline editing | Split, trim, offset, sequential arrangement, atomic edit batches |
| Soundtracks | Video audio and music mixing, gain, mute, stereo pan, fades |
| Export | H.264 / HEVC, configurable resolution/frame rate/bitrate, progress and cancellation |

Apple supports MP4/MOV and rational frame rates; Android supports MP4 and integer frame rates. Output is SDR, codec support depends on the device, and platform fonts/colors can differ. The library exports compositions; it does not include a live timeline player. [Full platform limits](Documentation/Guide.md#platform-architecture-and-limits).

### Built for SwiftUI workflows

Store `VideoProject` in `@State` or an `@Observable` model and export an immutable snapshot. Builders perform no media I/O, modifiers preserve identity, and editing/export actors keep their mutable state isolated. When rebuilding from view inputs, supply stable clip and track IDs from your model.

Use the library with SwiftUIComponents or any SwiftUI app; its public core has no SwiftUI dependency. Update UI on `MainActor` from `@Sendable` progress callbacks. The example editor debounces preview exports and cancels superseded work. [SwiftUI integration](Documentation/Guide.md#integrate-with-swiftuicomponents-or-another-swiftui-app) and [export model recipe](Documentation/Recipes.md#cancellable-export-from-swiftui).

### Rendering and performance

Visual transforms, filters, and layer composition run through GPU-backed pipelines. Timeline validation, animation evaluation, one-time text preparation, and audio processing use the CPU where required. Encoding uses platform media APIs and available codecs; hardware acceleration and throughput depend on the device.

Choose a smaller resolution for previews and the required delivery resolution for final exports. The example uses 640 x 360 previews; render tests use 320 x 180 fixtures while checking decoded video and audio. [Rendering architecture and performance guidance](Documentation/Guide.md#rendering-and-performance).

## Documentation and examples

| Resource | Start here for |
| --- | --- |
| [Full documentation](Documentation/README.md) | Topic index and library workflow |
| [Integration guide](Documentation/Integration.md) | SwiftPM, native Apple apps, Skip, and Kotlin |
| [Usage guide](Documentation/Guide.md) | Timelines, editing, effects, audio, export, and persistence |
| [API reference](Documentation/APIReference.md) | Public types, defaults, validation, and errors |
| [Composition recipes](Documentation/Recipes.md) | Image/title scenes, video-in-video, captions, crossfades, and SwiftUI |
| [SwiftVideo Studio example](Example/README.md) | Shared editor with playback, undo/redo, scrubbing, and 720p/1080p export |

Documentation is hosted in this GitHub repository. Select your dependency's release tag to read matching docs; `main` follows current development.

## Tests and coverage

[![iOS coverage](https://img.shields.io/badge/iOS%20lines-95.1%25-brightgreen)](Documentation/Coverage/ios.json)
[![Android Swift coverage](https://img.shields.io/badge/Android%20Swift%20core-94.8%25-brightgreen)](Documentation/Coverage/android-core.json)
[![Media3 coverage](https://img.shields.io/badge/Media3%20bridge-90.1%25-green)](Documentation/Coverage/android-media3.json)

Apple and Android CI exercise timeline rules, serialization, atomic edits, cancellation, destination protection, and real media exports. Integration tests independently decode frames and PCM audio to check placement, motion, filters, opacity, duration, and fades.

These coverage badges are the **0.0.1 verification snapshot**; the workflow badges above show live CI status. Android Swift core and Media3 bridge coverage measure separate layers. [Scope, thresholds, reports, and test commands](Documentation/Testing.md).

## Help and contribute

[Report a bug or request a feature](https://github.com/shial4/SwiftVideo/issues). Include your platform, SwiftVideo version, and a small reproducible composition for bugs. For code changes, follow the [test guide](Documentation/Testing.md) and include a test for the behavior you change.

If SwiftVideo is useful to you, **star the repository** to support the project and help other developers discover it.

## License

Copyright 2026 Software Deck Pty Ltd. Licensed under [Apache 2.0](LICENSE). See [NOTICE](NOTICE), [dependency licenses and corresponding source](Documentation/ThirdParty), and [example asset provenance](Example/ASSETS.md). SwiftVideo is not affiliated with CapCut or ByteDance.
