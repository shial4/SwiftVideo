<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Motion titles

[Documentation index](README.md) | [API reference](APIReference.md#animation) | [Platform integration](Integration.md)

This API is unreleased on the extensibility branch. It is not part of 0.0.1 or the 0.0.2 stabilization release.

`TextMotion` animates individual words or characters inside a text clip. The clip's transform and filters then apply to the complete title. Models are immutable, `Codable`, and `Sendable`, so applications can derive them from SwiftUI state and save them with a project.

On macOS, run the included example without supplying media assets:

```sh
swift run SwiftVideoExample motion-titles /tmp/motion-titles.mp4
```

It exports three short scenes showing typewriter, fade-up, and pop presets at 640 x 360. Choose an output path that does not already exist.

## Start with a preset

```swift
import Foundation
import SwiftVideo

let title = MediaClip.text(
    "Made with SwiftVideo",
    duration: try VideoTime(value: 3, timescale: 1),
    style: TextStyle(fontSize: 64, color: .white)
)
.textMotion(.fadeUp(
    duration: try VideoTime(value: 2, timescale: 5),
    stagger: try VideoTime(value: 1, timescale: 10),
    unit: .word,
    distance: 0.1
))
.transform(VisualTransform(x: 0.5, y: 0.5, width: 0.8, height: 0.3))

let project = VideoProject {
    MediaTrack("Title") { title }
}
try project.validate()
```

| Preset | Behavior |
| --- | --- |
| `.typewriter(stagger:unit:)` | Reveals each unit immediately at its start. Defaults to `.character`. |
| `.fadeUp(duration:stagger:unit:distance:)` | Fades from transparent to opaque while moving upward into place. Defaults to `.word` and a downward starting offset of 10% of the text layer height. |
| `try .pop(duration:stagger:unit:)` | Scales from 60% to 108%, then settles at 100%, with a fade-in. Defaults to `.word`. |

Stagger is the delay between successive units. Whitespace remains in the measured layout but does not consume a delay. Characters are Swift extended grapheme clusters, so combining marks and joined emoji stay together. Words are non-whitespace sequences; this is not a language-specific word tokenizer.

## Build your own motion

Use the same keyframes, Bezier timing curves, easing, and repetition controls as clip animation:

```swift
let motion = TextMotion(
    unit: .word,
    stagger: try VideoTime(value: 1, timescale: 10),
    animations: [
        KeyframeAnimation(property: .rotation, keyframes: [
            Keyframe(time: .zero, value: -5, easing: .easeInOut),
            Keyframe(time: try VideoTime(value: 1, timescale: 2), value: 5)
        ], repetition: .forever(autoreverses: true))
    ]
)
let animated = title.textMotion(motion)
let staticTitle = animated.textMotion(nil)
```

Each unit starts with `x = 0`, `y = 0`, `scale = 1`, `rotation = 0`, and `opacity = 1`. It is hidden before its stagger delay. Animation values replace these defaults. Translation is relative to the text layer's width and height, with positive y downward. Rotation is clockwise around the unit's bounds. This differs from a clip transform's x/y values, which position the layer's center on the project canvas.

`transform(forUnit:at:)` samples a unit for a custom preview. Pass the original clip effect time: `projectTime - clip.start + clip.effectsOffset`. Built-in renderers do this automatically. `speed(_:)` retimes the motion and stagger; trim and split preserve progress instead of restarting the title.

## Fonts, layout, and filters

Set `TextStyle.fontURL` to a readable local font file for portable typography; include its required license. Font names and glyph availability differ between platforms. Text is shaped and wrapped as a complete paragraph before units animate, so later words do not move earlier words. Optional ligatures are disabled for character animation. Required shaping clusters can still span logical characters; use word animation for scripts where splitting those clusters would be inappropriate.

Existing text color, alignment, and shadows also apply. Leave enough space in the text layer for its animation: glyphs moving outside the layer are clipped. A custom or built-in clip filter processes the composed title after its units have moved and blended. Whole-clip animation then positions that title in the project.

## Performance and limits

Font shaping and rasterization happen once per clip during export preparation. Apple reuses Core Image glyph images; Android packs glyphs into an atlas and reuses GL programs and textures. The CPU evaluates a small transform buffer each frame. The GPU moves, rotates, scales, fades, and composites the glyphs. Android uses a second GPU pass to preserve straight-alpha output for subsequent filters.

- A title supports 1...128 non-whitespace units. Use word animation or separate title scenes for longer captions.
- Stagger must be nonnegative. The final unit's first animation pass must fit within the original effect duration. Repetition can continue until the clip ends.
- Each title has a 64 MiB glyph raster budget. Android additionally requires a packed atlas no larger than 4096 x 4096. Reduce font size or split a large title if preparation exceeds these limits.
- Both built-in renderers advertise `.motionTitles`. A custom renderer must advertise and implement that capability; unsupported renderers reject the project before media work begins.
- The current export pipeline is SDR. Font rendering and encoded color can differ slightly across platforms.
