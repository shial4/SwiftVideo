<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Public API reference

[Documentation index](README.md) | [Usage guide](Guide.md) | [Recipes](Recipes.md)

Import `SwiftVideo` to use the public API below. `Foundation` supplies `URL`, `UUID`, and JSON encoding in the examples. Constructors build values unless marked `throws`; use `VideoProject.validate()` to validate a complete project. Validation does not open media files or guarantee device codec support.

## Time and frame rates

Source: [VideoTime.swift](../Sources/SwiftVideo/VideoTime.swift).

### VideoTime

An exact rational time conforming to `Hashable`, `Sendable`, `Comparable`, and `Codable`.

| Member | Contract |
| --- | --- |
| `init(value: Int64, timescale: Int32) throws` | Represents `value / timescale` seconds and normalizes the fraction. The timescale must be positive; `Int64.min` is rejected. Negative times are representable, but clip starts must be nonnegative. |
| `init(frames: Int64, rate: FrameRate) throws` | Converts a frame count to exact time at the supplied rate. |
| `zero` | Zero seconds. |
| `value`, `timescale` | Normalized numerator and denominator. |
| `seconds: Double` | Approximation for rendering/UI. Prefer rational time for editing and comparisons. |
| `adding(_:) throws`, `subtracting(_:) throws` | Checked arithmetic. Throws `timeOverflow` if the result cannot be represented without overflow or rounding. |
| Comparison operators | Compare rational values without converting to floating point. |

### FrameRate

`FrameRate` is `Hashable`, `Sendable`, and `Codable`. `init(numerator: Int32, denominator: Int32 = 1) throws` requires positive components and normalizes the fraction. Read `numerator`, `denominator`, or the approximate `framesPerSecond` value. Presets are `.fps24`, `.fps30`, and `.fps60`.

For NTSC-style timing, use `try FrameRate(numerator: 30_000, denominator: 1_001)`. The Apple renderer supports rational rates; Android currently requires a normalized denominator of `1`.

### VideoTimeRange

`init(start: VideoTime = .zero, duration: VideoTime)` creates a half-open interval. `start` is included and `end` is excluded. Both `end` and `contains(_:)` throw if end-time arithmetic overflows. The initializer itself does not validate the interval; edits validate their range requirements.

## Projects, tracks, and clips

Source: [VideoProject.swift](../Sources/SwiftVideo/VideoProject.swift) and [ProjectValidation.swift](../Sources/SwiftVideo/ProjectValidation.swift).

These models are immutable `Hashable`, `Codable`, and `Sendable` values. Tracks and clips also conform to `Identifiable` with `UUID` identities. JSON contains media URLs, not media bytes.

### VideoProject

```swift
VideoProject(canvas: VideoSize = .hd1080,
             frameRate: FrameRate = .fps30,
             background: VideoColor = .black,
             tracks: [MediaTrack] = [])
```

Read `canvas`, `frameRate`, `background`, and `tracks` directly.

| Member | Contract |
| --- | --- |
| `duration: VideoTime { get throws }` | Latest clip end across all tracks, including audio. An empty project has zero duration. |
| `visualClips(at:) throws -> [MediaClip]` | Active visual clips, back to front. Larger `zIndex` draws later. Ties preserve track order, then clip order. |
| `validate() throws` | Checks positive canvas dimensions, valid colors, unique track IDs, globally unique clip IDs, clip values, and representable duration. Does not inspect assets. |

Empty projects are valid editing state but cannot be exported. Transparent or uncovered areas use the project background. Overlaps are permitted, including within one track; tracks do not implicitly sequence clips.

### MediaTrack

`init(id: UUID = UUID(), name: String = "", clips: [MediaClip] = [])` groups clips. Its public properties are `id`, `name`, and `clips`. Use `VideoEditor` to change an existing project's tracks, or construct a new value.

### MediaSource

| Case/property | Meaning |
| --- | --- |
| `.video(URL)` | Video with optional source audio. |
| `.image(URL)` | A still image held for the clip duration. |
| `.text(String, TextStyle)` | A nonempty text overlay. |
| `.audio(URL)` | Audio without a visual layer. |
| `isVisual: Bool` | False only for `.audio`. |
| `hasAudio: Bool` | True for `.video` and `.audio`; this describes the source type, not whether a particular video file contains an audio stream. |
| `url: URL?` | The media URL; nil for text. |

Project validation accepts `file:`, HTTP(S), and Android `content:` media URLs. Readability, permissions, and decoder support are checked during export. Local files are the portable option; Apple cannot read Android content URLs.

### MediaClip

```swift
MediaClip(id: UUID = UUID(), source: MediaSource,
          start: VideoTime = .zero, duration: VideoTime,
          sourceStart: VideoTime = .zero, zIndex: Int = 0,
          transform: VisualTransform = VisualTransform(),
          filters: [MediaFilter] = [], animations: [KeyframeAnimation] = [],
          audio: AudioSettings = AudioSettings(),
          effectsOffset: VideoTime = .zero, effectsDuration: VideoTime? = nil)
```

All parameters are exposed as read-only properties. `effectsDuration` defaults to the initial `duration`.

- `start` places the clip on the project timeline. `sourceStart` chooses the first source-media time. Both must be nonnegative; `duration` must be positive.
- For video/audio, `sourceStart + duration` must fit readable source media. Choosing a duration does not loop, freeze, or change playback speed.
- `effectsOffset` and `effectsDuration` preserve the original animation/audio clock after edits. Leave their defaults for a new clip. A clip's `effectsOffset + duration` must not exceed `effectsDuration`.
- `timeRange` returns the clip's project interval.
- `visualTransform(at: VideoTime) throws` evaluates animation at project time. It does not check whether the clip is active; select active clips first.
- `audioGain(at: VideoTime) throws` evaluates the original fade envelope at project time and returns zero outside the clip's active range. It does not include stereo pan or the source waveform.

## Builders and clip modifiers

Source: [CompositionBuilder.swift](../Sources/SwiftVideo/CompositionBuilder.swift).

The builder initializers are:

```swift
VideoProject(canvas:frameRate:background:tracks:)
MediaTrack(_:id:clips:)
```

The first uses the same canvas/rate/background defaults as the array initializer. Its final closure produces tracks. `MediaTrack` defaults to an empty name and a fresh UUID; its final closure produces clips. Both are `rethrows` and propagate errors thrown while constructing their contents.

`VideoBuilder<Element: Sendable>` accepts single elements, arrays, `if`, `if let`, `if/else`, `for`, and availability branches. Its public compiler hooks are `buildExpression` for an element or array, `buildBlock`, `buildOptional`, both `buildEither` overloads, `buildArray`, and `buildLimitedAvailability`. Applications normally use the initializer closures rather than calling these hooks.

| Factory | Defaults |
| --- | --- |
| `MediaClip.video(_:duration:id:)` | URL, required duration, fresh ID |
| `MediaClip.image(_:duration:id:)` | URL, required duration, fresh ID |
| `MediaClip.audio(_:duration:id:)` | URL, required duration, fresh ID |
| `MediaClip.text(_:duration:style:id:)` | String, required duration, `TextStyle()`, fresh ID |

All factories start at project/source time zero with the standard `MediaClip` defaults.

| Modifier returning `MediaClip` | Behavior |
| --- | --- |
| `starting(at:)` | Replaces project start. |
| `sourceStarting(at:)` | Replaces source start. |
| `source(_:)` | Replaces source, retaining timing and effects. |
| `zIndex(_:)` | Replaces drawing order. |
| `transform(_:)` | Replaces the base transform. |
| `filter(_:)` | Appends one filter. |
| `filters(_:)` | Replaces all filters. |
| `audio(_:)` | Replaces audio settings. |
| `animate(_:keyframes:)` | Replaces the animation for the specified property. |
| `animations(_:)` | Replaces all animations. |

Modifiers preserve the ID and original effect clock, and do not mutate their receiver or validate the project. Pass stable IDs when deriving a project repeatedly from SwiftUI state. Use editing operations for split/trim; there is no duration modifier that silently resets the original effect clock.

## Visual style

Source: [VisualStyle.swift](../Sources/SwiftVideo/VisualStyle.swift). These style values are `Hashable`, `Codable`, and `Sendable`.

| Type | Constructor and values |
| --- | --- |
| `VideoSize` | `init(width: Int, height: Int)`. `.hd1080` is 1920 x 1080. Project dimensions must be positive; encoded output dimensions must also be even. |
| `VideoColor` | `init(red: Double, green: Double, blue: Double, alpha: Double = 1)`. Straight-alpha sRGB, finite components in `0...1`. Presets: `.black`, `.white`, `.clear`. |
| `VideoCrop` | `init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1)`. Normalized rectangle within the oriented source, with top-left origin. Positive width/height; the entire rectangle must fit within `0...1`. |
| `ContentMode` | `.fit` preserves aspect ratio inside the layer; `.fill` preserves aspect ratio while filling and clipping to the layer; `.stretch` fills without preserving aspect ratio. |

### VisualTransform

```swift
VisualTransform(x: Double = 0.5, y: Double = 0.5,
                width: Double = 1, height: Double = 1,
                scale: Double = 1, rotation: Double = 0, opacity: Double = 1,
                crop: VideoCrop = VideoCrop(), contentMode: ContentMode = .fit)
```

Every parameter is a read-only property. `x` and `y` locate the layer's center in normalized canvas coordinates with a top-left origin. Width and height are fractions of the canvas; scale multiplies the layer size. Rotation is clockwise in degrees. All numeric values must be finite, dimensions and scale positive, and opacity in `0...1`. Positions may place a layer partly or fully off canvas.

### MediaFilter

Filters run in array order. All arguments must be finite.

| Case | Accepted values |
| --- | --- |
| `.brightness(Double)` | `-1...1`; zero is unchanged. |
| `.contrast(Double)` | Nonnegative; one is unchanged. |
| `.saturation(Double)` | Nonnegative; one is unchanged, zero is grayscale. |
| `.gaussianBlur(Double)` | Nonnegative radius; zero is unchanged. Native filter pipelines may differ slightly. |
| `.sepia(Double)` | `0...1` intensity. |

### TextStyle and TextShadow

`TextStyle` exposes `fontName: String? = nil`, `fontURL: URL? = nil`, `fontSize: Double = 48`, `color: VideoColor = .white`, `alignment: TextAlignment = .center`, and `shadow: TextShadow? = nil` through its initializer and read-only properties. `TextAlignment` is `.leading`, `.center`, or `.trailing`.

`TextShadow` exposes `color: VideoColor = .black`, `radius: Double = 2`, `x: Double = 1`, and `y: Double = 1`. Shadow values must be finite and radius nonnegative.

Font size must be finite and positive. Font size and shadow dimensions use project canvas pixels and scale with export resolution. Text wraps inside the clip's layer bounds and is rasterized once per clip before GPU transforms. Keep those bounds large enough for the intended text; each resulting bitmap dimension must be positive and at most 8192 pixels. Use a readable local `fontURL` for portable typography; platform font names and glyph availability differ. The caller must include the font's required license.

## Animation

- `AnimationProperty` cases: `.x`, `.y`, `.scale`, `.rotation`, `.opacity`.
- `Keyframe(time: VideoTime, value: Double, easing: Easing = .linear)` exposes those three values. Time is relative to the original clip's effect clock, not project time.
- `KeyframeAnimation(property: AnimationProperty, keyframes: [Keyframe])` exposes `property` and `keyframes`. `value(at:) -> Double?` interpolates at effect time, holds the first/last value outside their range, and returns nil for an empty array. An empty array is invalid in a project.
- A clip may have one animation per property. Keyframe times must increase strictly from zero or later through `effectsDuration`. Values must be finite; opacity must remain in `0...1` and scale positive.
- Animated values replace the corresponding base transform value. Width, height, crop, and content mode are not keyframe properties.

`Easing` applies to the segment leaving a keyframe. Its `value(at: Double) -> Double` clamps progress to `0...1` and evaluates `.linear`, `.easeIn` (quadratic), `.easeOut` (quadratic), `.easeInOut` (smoothstep), or `.step` (hold until the segment ends).

## Audio

`AudioSettings(volume: Double = 1, isMuted: Bool = false, pan: Double = 0, fadeIn: VideoTime = .zero, fadeOut: VideoTime = .zero)` exposes all five properties.

- Volume is a finite, nonnegative gain multiplier. Pan is finite in `-1...1`, from left to right, using constant-power stereo panning.
- Fades are linear, nonnegative, and their combined duration must fit within `effectsDuration`.
- `gain(at: VideoTime, duration: VideoTime) -> Double` evaluates volume and fades in effect-relative time. It returns zero when muted or outside the half-open duration, and does not apply pan.
- Video audio is enabled by default. Mute the background video's audio if a separate commentary or music track should replace it.
- Output audio is mixed to stereo AAC. Overlapping sources are mixed and limited at full scale; leave headroom. Android's mixing path accepts mono/stereo PCM, not surround processing.

Use `MediaClip.audioGain(at:)` for project-time evaluation after trimming or splitting. See the [crossfade recipe](Recipes.md#visual-and-audio-crossfade).

## Editing

Source: [VideoEditor.swift](../Sources/SwiftVideo/VideoEditor.swift).

`VideoEditor` is an actor. `init(project: VideoProject = VideoProject()) throws` validates its starting state. `await editor.snapshot()` returns an immutable snapshot. `try await editor.apply(_ edits: [VideoEdit])` returns the new snapshot and commits only if every edit and the final project are valid. On failure, the previous state is unchanged.

| `VideoEdit` case | Behavior |
| --- | --- |
| `.addTrack(MediaTrack)` | Appends a track. |
| `.removeTrack(UUID)` | Removes the track and its clips. |
| `.addClip(MediaClip, trackID: UUID)` | Appends a clip to the named track. |
| `.replaceClip(MediaClip)` | Replaces the existing clip with the same ID, in its current track. |
| `.removeClip(UUID)` | Removes a clip by ID. |
| `.split(UUID, at: VideoTime, rightID: UUID)` | Splits strictly inside the clip at absolute project time. The left clip retains its ID; supply a new, unique right ID. Source offsets and effect timing are preserved. |
| `.trim(UUID, keeping: VideoTimeRange)` | Keeps a nonempty range relative to the current clip's beginning. Advances project/source start and effect offset; does not ripple other clips. |
| `.offset(UUID, by: VideoTime)` | Moves project start by a signed amount. The resulting start must remain nonnegative. |
| `.mergeSequentially([MediaClip], trackID: UUID, start: VideoTime)` | Appends the supplied clips at consecutive project starts. Keeps individual sources, IDs, trims, and effects; does not flatten or re-encode them. Existing clips remain. |

Track and clip IDs must remain unique after the batch. A missing edit target throws `missingTrack` or `missingClip`. Undo/redo is application-owned; retain snapshots as the example editor does.

## Export

Source: [VideoExporter.swift](../Sources/SwiftVideo/VideoExporter.swift).

### ExportSettings

```swift
ExportSettings(resolution: VideoSize? = nil, frameRate: FrameRate? = nil,
               codec: VideoCodec = .h264, container: VideoContainer = .mp4,
               quality: Double = 0.8, videoBitRate: Int? = nil,
               audioBitRate: Int = 192_000)
```

Settings are `Hashable`, `Codable`, and `Sendable`; every parameter is a read-only property. Nil resolution/rate uses the project value. `VideoCodec` is `.h264` or `.hevc`; `VideoContainer` is `.mp4` or `.mov`.

- `validate(for: VideoProject) throws` checks positive even output dimensions, finite quality in `0...1`, and positive bitrates fitting a signed 32-bit integer. Renderer-specific constraints are checked separately.
- `effectiveVideoBitRate(for:) throws -> Int` uses an explicit bitrate when provided. Otherwise it estimates `width * height * fps * (0.04 + quality * 0.16)`, with a minimum of 128,000 bits/second and a checked 32-bit upper bound.
- Both built-in renderers limit output to 8192 pixels per dimension and 240 fps. Device encoder limits may be lower. Apple supports MP4/MOV and rational rates; Android supports MP4 and integer rates. Output is SDR.

### VideoExporter

`VideoExporter` is an actor. `init()` chooses the built-in renderer on Apple or Android. `init(renderer: any VideoRendering)` injects a renderer. Read `await exporter.capabilities` before selecting supported engine features.

```swift
@discardableResult
func export(_ project: VideoProject, to destination: URL,
            settings: ExportSettings = ExportSettings(),
            progress: @escaping @Sendable (ExportProgress) -> Void = { _ in }) async throws -> URL
```

Only one export may be active per exporter. Use separate instances for independent exports. The project, settings, and renderer capabilities are validated before rendering.

The destination must be a new local file URL in an existing writable directory. Use a filename extension matching the selected container. The exporter writes to a staging file beside the destination and moves it into place only after success. It never overwrites an existing destination, including one created concurrently. Failure or cancellation removes its staging file.

Cancel the task awaiting `export`, or call `await exporter.cancel()`. Await the export's completion to know cleanup has finished; `cancel()` requests cancellation and is not a completion barrier. Cancellation surfaces as `VideoError.cancelled`. Create the output directory yourself before export.

### ExportProgress

`ExportProgress(phase:fraction:)` is `Sendable` and `Equatable`. Its read-only `phase` uses the nested `ExportProgress.Phase` enum: `.preparing`, `.rendering`, `.finishing`, or `.completed`. `Phase` is a `String`-backed, `Sendable` enum. The initializer clamps `fraction` to `0...1`.

The callback is `@Sendable` and may run off the main actor. Keep it lightweight and hop to `MainActor` to update UI. Progress is an estimate, not an elapsed-time guarantee; use successful return from `export` as completion. See the [SwiftUI recipe](Recipes.md#cancellable-export-from-swiftui).

## Renderer contract

`VideoRendering: Sendable` requires synchronous `capabilities: RendererCapabilities { get }` and:

```swift
func render(_ project: VideoProject, to destination: URL,
            settings: ExportSettings,
            progress: @escaping @Sendable (ExportProgress) -> Void) async throws
```

Implementations must finish a playable file or throw, poll task cancellation, and release all media resources before returning. When called through `VideoExporter`, the destination is its staging URL. The exporter checks for nonempty output; it does not independently decode a custom renderer's result. Do not retain callbacks or keep writing after `render` returns.

`RendererCapabilities(name:features:codecs:containers:)` stores a `String`, `Set<CompositionFeature>`, `Set<VideoCodec>`, and `Set<VideoContainer>`. All properties are read-only. `validate(_:settings:) throws` rejects unavailable codec/container combinations and features required by the project's clips. It does not probe device codecs, validate all project values, or load media.

`CompositionFeature` cases are `.video`, `.images`, `.text`, `.filters`, `.animation`, `.audioMixing`, `.audioFades`, `.audioPan`, and `.customFonts`.

| Built-in renderer | Availability and responsibilities |
| --- | --- |
| `AppleVideoRenderer()` | Apple platforms with AVFoundation. Actor using AVFoundation codecs and Metal-backed Core Image. Requires Metal; supports all composition features and both listed codecs/containers, subject to the device. |
| `AndroidVideoRenderer()` | Android only. Actor using native Swift evaluation and the Swift-authored Skip Media3 service. Requires an initialized app/JVM context; supports all composition features, both codecs, and MP4, subject to the device. |

Both expose nonisolated capabilities and the `render` method. Prefer `VideoExporter` to obtain destination protection and cancellation/error normalization. See [GPU and CPU responsibilities](Guide.md#rendering-and-performance) for the performance boundary.

## Errors and troubleshooting

Source: [VideoError.swift](../Sources/SwiftVideo/VideoError.swift). `VideoError` conforms to `Error`, `Sendable`, `Equatable`, and `LocalizedError`; `errorDescription` provides a human-readable message.

| Case | Response |
| --- | --- |
| `.invalidTime(String)` | Use positive time scales/rate components and representable values. |
| `.timeOverflow` | Reduce an unrepresentable time calculation; do not silently convert to floating-point editing. |
| `.invalidProject(String)` | Inspect duplicate IDs, clip ranges, colors, transforms, fades, or keyframes. Call `validate()` before export. |
| `.missingTrack(UUID)`, `.missingClip(UUID)` | Refresh selection from the latest editor snapshot; do not reuse stale IDs. |
| `.unsupportedFeature(String)` | Change unsupported settings or renderer. On Android use MP4 and an integer rate. On Apple ensure Metal is available. |
| `.invalidMedia(String)` | Check file readability, source duration, font access, permissions, and decoder support. |
| `.invalidExport(String)` | Check destination URL, even dimensions, quality, and bitrate. |
| `.destinationExists` | Select a new URL. The exporter does not replace files. |
| `.exportInProgress` | Await/cancel the active operation or use a separate exporter. |
| `.cancelled` | Treat a requested cancellation as a normal user action. |
| `.renderingFailed(String)` | Inspect the message and device codec/file-system conditions. This also wraps unexpected rendering and file errors. |

If a title is clipped, increase the text layer's bounds or reduce font size. If a picture-in-picture clip covers the entire canvas, set its `VisualTransform.width` and `height`; a new clip defaults to full-canvas bounds. If audio is unexpectedly doubled, mute the background video before adding separate commentary. If a restored project cannot read media, restore or relink its referenced files; project JSON never embeds them.

For reproducible test/build commands and the measured coverage scope, see [Testing](Testing.md).
