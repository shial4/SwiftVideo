<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Masks and chroma key

[Documentation index](README.md) | [API reference](APIReference.md#mediafilter) | [Custom effects](CustomEffects.md)

These APIs are unreleased on the extensibility branch. They are not part of 0.0.1 or the 0.0.2 stabilization release.

Use `.mask` to keep a shaped region of an image, video, or title. Use `.chromaKey` to make a selected color transparent, revealing the layers underneath. Both are ordinary `MediaFilter` values: append them to a clip or track, combine them with other filters, and save them in project JSON.

## Round a commentary video

```swift
import Foundation
import SwiftVideo

func commentary(footage: URL, presenter: URL, duration: VideoTime) -> VideoProject {
    VideoProject {
        MediaTrack("Footage") {
            MediaClip.video(footage, duration: duration)
        }
        MediaTrack("Presenter") {
            MediaClip.video(presenter, duration: duration)
                .filter(.mask(VideoMask(shape: .ellipse, feather: 0.02)))
                .transform(VisualTransform(x: 0.8, y: 0.75, width: 0.25, height: 0.35))
                .zIndex(1)
        }
    }
}
```

`VideoMask(shape:bounds:feather:inverted:)` defaults to an ellipse over the complete source, with no feather and no inversion. Shapes are `.ellipse` and `.rectangle`.

- `bounds` is a `VideoCrop` with normalized top-left coordinates. The whole rectangle must fit inside the oriented source.
- `feather` fades inward from the boundary. It is a fraction of the mask's shortest side, from zero to 0.5. Ellipse feathering follows concentric ellipses. Zero retains a one-source-pixel antialiased edge.
- `inverted: true` keeps the outside instead of the inside, including the complementary feather.

A source's aspect ratio and the clip's placement determine whether an ellipse appears circular. For a square source, give the layer equal width and height in output pixels. Mask settings remain in source coordinates when export resolution changes.

## Remove a green background

```swift
func greenScreen(presenter: URL, background: URL, duration: VideoTime) -> VideoProject {
    VideoProject {
        MediaTrack("Background") {
            MediaClip.image(background, duration: duration)
        }
        MediaTrack("Presenter") {
            MediaClip.video(presenter, duration: duration)
                .filter(.chromaKey(ChromaKey(
                    color: VideoColor(red: 0, green: 1, blue: 0),
                    tolerance: 0.1,
                    softness: 0.1
                )))
                .zIndex(1)
        }
    }
}
```

The defaults above key pure green. Supply an opaque sRGB `VideoColor` sampled from your background. `tolerance` removes colors within a normalized linear-RGB distance of that color. `softness` adds a smooth transition beyond that distance. Each lies in `0...1`, and their sum cannot exceed one. Zero softness creates a hard threshold, with a small numerical transition to avoid division by zero.

For example, increasing tolerance removes a wider range of background shades, but may also remove similarly colored foreground content. Increasing softness makes the edge more gradual. Existing source transparency is preserved. This is color-based keying, without automatic subject detection or spill suppression; green reflections, hair, motion blur and uneven lighting may need a custom effect or segmentation.

## Ordering, tracks and SwiftUI

Filters run in authored order before the clip's crop, content-mode fitting, transform and placement. A track's filters follow each visual clip's filters; they do not process the flattened track. For example:

```swift
func maskedTrack(clips: [MediaClip], feather: Double) -> MediaTrack {
    MediaTrack(name: "Windows", clips: clips)
        .filter(.mask(VideoMask(shape: .rectangle,
            bounds: VideoCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            feather: feather)))
}
```

These immutable `Hashable`, `Codable`, `Sendable` values can be derived from SwiftUI controls like the existing transform settings. Keep clip and track IDs stable when rebuilding a project. Build and validate a snapshot before starting `VideoExporter`; changing UI state does not mutate an export already in progress.

## Rendering and limits

Apple uses the existing Metal-backed Core Image context. Shape masks cache their lazy gradient graph for each input extent. Chroma key uses color polynomials, distance, threshold and compositing operations on the GPU. Android uses the existing Media3 shader lifecycle with a single fragment-shader pass per mask or key. Neither implementation downloads source pixels to the CPU or creates a per-frame bitmap.

The renderers declare `.masks` and `.chromaKey` capabilities. Unsupported renderers fail capability validation before rendering. The current output contract is SDR. Platform color conversion can change colors close to a key threshold, so tune the key using representative footage on both platforms. MP4/H.264 or HEVC output is composited over the project background; these filters do not add an alpha-channel export format.

Static image masks, animated mask parameters, arbitrary paths and AI segmentation are separate capabilities and are not included in these shape-mask APIs. Whole-layer animation still moves, rotates, scales and fades the masked result.
