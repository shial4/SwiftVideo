<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo usage guide

[Documentation index](README.md) | [Public API reference](APIReference.md) | [Composition recipes](Recipes.md)

A Swift package for programmatic video composition on iOS, macOS, and Android.
The `SwiftVideo` product provides immutable timeline models, transactional editing,
and asynchronous video export. It can be consumed by SwiftUIComponents or another
Swift application without adding UI dependencies to the composition engine.

Requires Swift 6.3 or later, iOS 17 or macOS 14, and a matching Swift Android SDK
for Android builds. Android applications use Skip Fuse with an initialized Skip
Android context. Media3 Transformer 1.11.1 provides the Android media backend.

## Use from a Swift package

Add this repository as a Swift Package Manager dependency and add its `SwiftVideo`
product to your target. For a local checkout:

```swift
.package(path: "../SwiftVideoComposition")
// In your target's dependencies:
.product(name: "SwiftVideo", package: "SwiftVideoComposition")
```

```swift
import SwiftVideo

let duration = try VideoTime(value: 5, timescale: 1)
let project = VideoProject(tracks: [
    MediaTrack(name: "Footage", clips: [
        MediaClip(source: .video(inputURL), duration: duration)
    ]),
    MediaTrack(name: "Title", clips: [
        MediaClip(source: .text("Hello", TextStyle(fontSize: 96)),
                  duration: duration, zIndex: 1)
    ])
])
let exporter = VideoExporter()
try await exporter.export(project, to: outputURL,
                          settings: ExportSettings(resolution: .hd1080)) { progress in
    // This Sendable callback is not guaranteed to run on MainActor.
    print(progress.fraction)
}
```

Use `Task { @MainActor in ... }` to update SwiftUI state from progress callbacks.
Cancel the calling task or call `await exporter.cancel()`. One exporter handles
one operation at a time. Use separate instances for independent exports.
Existing destinations are preserved. A failed or cancelled export removes its
staging file; the destination appears only after a successful export.

## Timeline and editing

`VideoProject`, `MediaTrack`, and `MediaClip` are `Codable`, `Hashable`, and
`Sendable` values. Project JSON stores media references, not the referenced files.
Call `validate()` after decoding; editors and exporters also validate input.

`VideoTime` uses a normalized rational value and checked arithmetic. Construct
frame times with `VideoTime(frames:rate:)`; use `FrameRate(numerator:denominator:)`
for rates such as 30000/1001. Clip ranges include their start and exclude their
end. The project duration is the latest clip end, including audio-only tracks.

`VideoEditor` owns mutable editing state. `apply(_:)` commits an entire edit batch
only when the resulting project is valid. Supported edits add/remove tracks and
clips, replace clips, split, trim, offset, and arrange clips sequentially:

```swift
let track = MediaTrack(name: "Footage")
let editor = try VideoEditor(project: VideoProject(tracks: [track]))
let edited = try await editor.apply([
    .mergeSequentially(clips, trackID: track.id, start: .zero)
])
```

Splits use absolute project time. Trims retain a range relative to the current
clip start and leave a gap rather than rippling other clips. Both preserve the
source offset and the original animation/fade clock. Sequential merging retains
individual clips and effects; it does not flatten or re-encode source media.

## Visuals and audio

- Clips may overlap within or across tracks. Larger `zIndex` values draw above
  smaller values. At equal values, later clips in track order draw above earlier
  clips. Empty areas show the project background.
- Transform positions describe the layer center in normalized canvas coordinates
  with a top-left origin. Width and height are relative to the canvas; rotation
  is clockwise in degrees. Crop coordinates are relative to the oriented source.
  Fit, fill, stretch, opacity, and scale support overlays and picture-in-picture.
- Keyframes animate position, scale, rotation, and opacity. Easing belongs to the
  outgoing segment. Overlap two clips and animate opacity to make a visual fade.
- Filters provide brightness, contrast, saturation, Gaussian blur, and sepia.
  Filters are applied in array order. Native color pipelines and font rasterizers
  can produce small platform differences; output is SDR, without HDR preservation.
- Text wraps within the clip's width and height, rasterized once into a transparent
  bitmap at export resolution before GPU transforms. Font size and shadow dimensions use project pixels and scale with
  export resolution. Supply a local font file for portable typography; platform
  font names and available glyphs differ between operating systems.
- Audio sources and unmuted video audio mix into stereo AAC. Settings include
  volume, mute, equal-power pan, and linear fade-in/out. Overlap clips for audio
  crossfades. Summed signals are limited at full scale, so leave headroom when
  mixing. Android accepts mono/stereo PCM; surround processing is not provided.

## Platform architecture and limits

`VideoRendering` separates the public timeline from rendering. You can inspect
`await exporter.capabilities` or inject a renderer. Capabilities describe engine
features; the device must also provide a compatible decoder and encoder.

| Backend | Implementation | Export |
| --- | --- | --- |
| Apple | AVFoundation decoding/writing, Core Image composition, Core Animation text | H.264/HEVC, MP4/MOV, rational frame rates |
| Android | Native Swift timeline plus a Skip-transpiled `SwiftVideoMedia3` service using Media3 Transformer | H.264/HEVC, MP4, integer frame rates |

Apple uses `AVVideoComposition.Configuration` on iOS 26/macOS 26 and later, with
an asynchronous AVFoundation compatibility path on older supported systems.
Android models, editing, validation, and animation evaluation remain native Swift.
The small JVM service is authored in Swift with `#if SKIP`. Generated Kotlin and
Gradle output must not be edited. Skip metadata lives in each target's `Skip`
directory. No public API requires Kotlin, AVFoundation, or Media3 types.

Both renderers reject outputs above 8192 pixels per dimension or 240 fps; actual
device limits may be lower. Output dimensions must be positive and even. Android
uses microsecond media timestamps and currently rejects fractional frame rates.
Apple cannot read Android `content:` URLs. Local files are the portable input
choice; access to network/content sources depends on platform permissions and
decoder support. HEVC availability depends on the device. Export failures surface
as `VideoError`; unsupported requests fail rather than silently dropping effects.

## Add animation, images, and music

Build clips, put them in tracks, then pass one project snapshot to the exporter. Clip duration is the selected source range, not a request to loop or slow down the input. For a media file, `sourceStart + duration` must fit the source.

```swift
let four = try VideoTime(value: 4, timescale: 1)
let half = try VideoTime(value: 1, timescale: 2)
let title = MediaClip(
    source: .text("CHASE THE LIGHT", TextStyle(fontSize: 96, shadow: TextShadow(radius: 6))),
    duration: four, zIndex: 10,
    transform: VisualTransform(y: 0.75, width: 0.9, height: 0.3),
    animations: [
        KeyframeAnimation(property: .opacity, keyframes: [
            Keyframe(time: .zero, value: 0),
            Keyframe(time: half, value: 1)
        ]),
        KeyframeAnimation(property: .y, keyframes: [
            Keyframe(time: .zero, value: 0.9, easing: .easeOut),
            Keyframe(time: half, value: 0.75)
        ])
    ]
)
let inset = MediaClip(
    source: .image(imageURL), duration: four, zIndex: 5,
    transform: VisualTransform(x: 0.8, y: 0.25, width: 0.3, height: 0.3,
                               rotation: 5, contentMode: .fill),
    filters: [.saturation(1.2), .contrast(1.1)]
)
let soundtrack = MediaClip(
    source: .audio(musicURL), duration: four,
    audio: AudioSettings(volume: 0.5, fadeIn: half, fadeOut: half)
)
let project = VideoProject(tracks: [
    MediaTrack(name: "Footage", clips: [
        MediaClip(source: .video(videoURL), duration: four,
                  audio: AudioSettings(isMuted: true))
    ]),
    MediaTrack(name: "Overlays", clips: [title, inset]),
    MediaTrack(name: "Music", clips: [soundtrack])
])
```

To make a dissolve, overlap two clips and animate the upper clip's opacity from zero to one. For an audio crossfade, overlap audio clips with opposing `fadeIn` and `fadeOut` durations. There is no separate transition object.

## Select an export format

```swift
let settings = ExportSettings(
    resolution: VideoSize(width: 1280, height: 720),
    frameRate: .fps30,
    codec: .h264,
    container: .mp4,
    quality: 0.8,
    videoBitRate: 4_000_000,
    audioBitRate: 192_000
)
try await VideoExporter().export(project, to: outputURL, settings: settings)
```

An explicit video bitrate overrides the quality-based bitrate estimate. Resolution and frame rate default to the project's canvas and frame rate. Codec support is device-dependent, so handle export errors even after checking capabilities.

## Integrate with SwiftUIComponents or another SwiftUI app

1. Add the `SwiftVideo` product to the target that owns editing state. The library has no dependency on SwiftUIComponents.
2. Keep the current `VideoProject` in your app's observable model. Use `VideoEditor.apply` for edits and publish the returned snapshot on `MainActor`.
3. Start export in a cancellable `Task`. The progress callback can run off the main actor; dispatch UI updates to `MainActor`.
4. Play the resulting URL with your platform's player. SwiftVideo exports compositions; it does not supply a live timeline player. The example renders a lower-resolution preview after edits and then plays it.
5. Keep access to imported files valid until export finishes. The caller owns media picking, security-scoped access, file lifetime, permissions, and destination selection.

See the working [EditorStore](../Example/Sources/SwiftVideoEditor/EditorStore.swift) for snapshot history, debounced preview generation, cancellation, and progress handling. [EditorDocument](../Example/Sources/SwiftVideoEditor/EditorDocument.swift) shows a complete composition.

### Declarative composition

`VideoProject { MediaTrack { ... } }` builds ordinary `Codable`, `Sendable` values. It has no SwiftUI dependency and performs no decoding, file access, or rendering. Builders support `if`, `if let`, `if/else`, `for`, reusable arrays, and throwing expressions. Existing array-based initializers remain available.

```swift
let project = VideoProject {
    MediaTrack("Footage", id: footageTrackID) {
        MediaClip.video(url, duration: duration, id: footageID)
            .sourceStarting(at: sourceOffset)
            .filter(.saturation(1.2))
    }
    if showCaptions {
        MediaTrack("Captions", id: captionTrackID) {
            for caption in captions {
                MediaClip.text(caption.text, duration: caption.duration, id: caption.id)
                    .starting(at: caption.start).zIndex(10)
                    .transform(VisualTransform(y: 0.9, width: 0.9, height: 0.12))
            }
        }
    }
}
```

Supply stable IDs from your observable model when deriving a project repeatedly from view inputs. Default IDs are fresh UUIDs on each construction. Modifiers return a new clip while retaining its ID, source range, and original animation/fade clock. `.filter` appends; `.filters` replaces the list. `.animate` replaces the animation for one property; `.animations` replaces all animations. Timing and visual validation remain in `VideoProject.validate`, `VideoEditor`, and export, so the DSL and array APIs share the same rules.

Keep the project in model state rather than starting exports from `View.body`. Use a cancellable `.task(id:)` or model-owned task for preview generation, debounce rapid changes, and guard against old completion callbacks replacing newer state. The example implements these controls and uses a separate exporter for final output.

## Rendering and performance

| Work | Apple | Android |
| --- | --- | --- |
| Decode / encode | AVFoundation platform codecs | Media3 / MediaCodec platform codecs |
| Crop, fit, rotation, opacity, filters, composition | Core Image on Metal | Media3 OpenGL effects and compositor |
| Text preparation | One Core Animation bitmap per text clip | One Android text bitmap per text clip |
| Timeline, validation, keyframes, audio gain/mixing | CPU | CPU |

Apple exports share a thread-safe Metal-backed `CIContext`, use IOSurface-backed Metal-compatible pixel buffers, and disable intermediate-image caching for changing video frames. Visual ordering is computed once per export. No CPU pixel loop applies visual filters or blends layers. A Metal-capable GPU is required. This follows Apple's [Core Image video guidance](https://developer.apple.com/videos/play/wwdc2020/10008/).

Android delegates graphical operations to [Media3 Transformer's OpenGL pipeline](https://developer.android.com/media/media3/transformer). Native Swift evaluates timeline and animation values; the Swift-authored Skip service supplies those values to Media3. Text is prepared at layer bounds, rather than allocating a full output-sized image for each caption, and its position/opacity animation runs through the graphical pipeline.

Codec selection remains with the platform; hardware availability depends on the device, codec, resolution, and concurrent workloads. Emulators may use software codecs or a software graphics implementation. Tests verify output behavior, not a universal throughput or hardware-utilization guarantee. Profile a release build on target devices before setting product limits. CPU audio mixing and one-time text rasterization remain deliberate boundaries; the library does not claim zero CPU usage.

On Apple platforms, obtain a video's duration before choosing a clip range:

```swift
import AVFoundation

let asset = AVURLAsset(url: inputURL)
let mediaDuration = try await asset.load(.duration)
let duration = try VideoTime(value: mediaDuration.value, timescale: mediaDuration.timescale)
```

On Android, obtain duration and readable file/content URLs from your app's media-import layer. The demo uses known-duration bundled clips. The composition package does not present media pickers or copy arbitrary user media for you.

## Save and restore a project

```swift
let data = try JSONEncoder().encode(project)
try data.write(to: projectURL, options: .atomic)
let restored = try JSONDecoder().decode(VideoProject.self, from: Data(contentsOf: projectURL))
try restored.validate()
```

Project JSON contains URLs, not embedded media. Copy media into durable app storage and update its references if you need projects to survive temporary file deletion or transfer between devices. Treat imported JSON as untrusted input and handle validation errors.

## Handle errors and cancellation

`VideoError` distinguishes invalid time/project/media/export settings, missing editing targets, unsupported features, destination conflicts, rendering failures, cancellation, and an already-running export. Catch errors at the app boundary and present a useful message. Do not retry unsupported codecs or missing files without changing the input.

A `VideoExporter` accepts one export at a time. `await exporter.cancel()` cancels its active operation; cancelling the caller's task does the same. Keep the exporter or task in your observable model if a Cancel button needs access to it. A destination that already exists is never overwritten.

## Command-line example

On macOS, render the deterministic integration composition:

```sh
swift run SwiftVideoExample milestone Tests/SwiftVideoTests/Resources/Milestone /tmp/milestone.mp4
```

Or render saved project JSON:

```sh
swift run SwiftVideoExample export project.json output.mp4
```

For platform builds, coverage, and limitations of the test environment, see [Testing](Testing.md).
