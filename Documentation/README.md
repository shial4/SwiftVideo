<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo documentation

SwiftVideo is a Swift video composition library for iOS 17+, macOS 14+, and Android API 28+ through Skip Fuse. This documentation describes the public `SwiftVideo` product for version 0.0.1.

Start with [installation and your first export](../README.md#install), then follow the [usage guide](Guide.md). The pages below render directly on GitHub and are included in the package checkout.

## Documentation

| Page | Contents |
| --- | --- |
| [Integration guide](Integration.md) | SwiftPM, native iOS/macOS, shared Skip apps, and a native Android/Kotlin wrapper |
| [Usage guide](Guide.md) | Installation, timeline semantics, editing, effects, audio, export, SwiftUI integration, persistence, and performance |
| [Public API reference](APIReference.md) | Public types, constructors, defaults, methods, validation rules, renderer contracts, and errors |
| [Composition recipes](Recipes.md) | Complete functions for an image/title scene, commentary video with captions, crossfades, and a cancellable SwiftUI export model |
| [Example editor](../Example/README.md) | Build and run the shared SwiftUI editor on Apple and Android |
| [Tests and coverage](Testing.md) | Test scope, measured coverage, CI gates, and commands to reproduce results |
| [Dependency notices](ThirdParty/README.md) | Third-party licenses and corresponding source |

## Find a topic

- [Exact time and frame rates](APIReference.md#time-and-frame-rates)
- [Projects, tracks, and clips](APIReference.md#projects-tracks-and-clips)
- [Declarative builders and immutable modifiers](APIReference.md#builders-and-clip-modifiers)
- [Coordinates, crop, filters, and text](APIReference.md#visual-style)
- [Animation and easing](APIReference.md#animation)
- [Audio, gain, pan, and fades](APIReference.md#audio)
- [Atomic editing, splitting, and trimming](APIReference.md#editing)
- [Export settings, progress, and cancellation](APIReference.md#export)
- [Renderer capabilities and custom renderers](APIReference.md#renderer-contract)
- [Errors and troubleshooting](APIReference.md#errors-and-troubleshooting)
- [SwiftUI and SwiftUIComponents integration](Guide.md#integrate-with-swiftuicomponents-or-another-swiftui-app)
- [GPU and CPU responsibilities](Guide.md#rendering-and-performance)
- [Platform support and limitations](Guide.md#platform-architecture-and-limits)
- [Save and restore project JSON](Guide.md#save-and-restore-a-project)

## Model and workflow

1. Obtain readable media URLs from your application's import layer.
2. Create a `VideoProject` containing `MediaTrack` and `MediaClip` values.
3. Call `validate()` or use `VideoEditor` to apply a validated edit batch.
4. Pass an immutable project snapshot to `VideoExporter`.
5. Play or share the returned file URL using your application's player and sharing UI.

Builders create values without loading media. Export performs media I/O and rendering. Your application owns source-file lifetime, permissions, media selection, playback, and undo history. See the [working editor store](../Example/Sources/SwiftVideoEditor/EditorStore.swift) for those integration patterns.

## Documentation versions

The `main` branch documents current development. For a released dependency, use the same tag in GitHub's branch selector so the documentation and source agree. The [release page](https://github.com/shial4/SwiftVideo/releases) lists published versions.

The library uses Metal-backed Core Image on Apple and Media3's OpenGL pipeline on Android. Codec availability remains device-dependent. Output is SDR, and the library does not include a live timeline player. Review the platform limits before selecting product requirements.
