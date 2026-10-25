<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Composition recipes

[Documentation index](README.md) | [Public API reference](APIReference.md) | [Usage guide](Guide.md)

The functions below use the public library API. Supply readable media URLs from your application. Video/audio sources must contain the selected duration; images are held for their clip duration. Building or validating a project does not decode its media.

## Image and text title scene

This four-second scene places a photo beside a title over a video background. The title fades in during the first half-second. Its times are relative to the title clip's effect clock.

```swift
import Foundation
import SwiftVideo

func makeTitleScene(footageURL: URL, photoURL: URL) throws -> VideoProject {
    let four = try VideoTime(value: 4, timescale: 1)
    let half = try VideoTime(value: 1, timescale: 2)
    let project = VideoProject {
        MediaTrack("Background") {
            MediaClip.video(footageURL, duration: four)
                .audio(AudioSettings(isMuted: true))
        }
        MediaTrack("Title scene") {
            MediaClip.image(photoURL, duration: four)
                .zIndex(1)
                .transform(VisualTransform(x: 0.22, y: 0.5,
                                           width: 0.34, height: 0.72,
                                           rotation: -3, contentMode: .fill))
            MediaClip.text("A NEW PERSPECTIVE", duration: four,
                           style: TextStyle(fontSize: 80,
                                            shadow: TextShadow(radius: 4)))
                .zIndex(2)
                .transform(VisualTransform(x: 0.7, y: 0.5,
                                           width: 0.5, height: 0.4))
                .animate(.opacity, keyframes: [
                    Keyframe(time: .zero, value: 0, easing: .easeOut),
                    Keyframe(time: half, value: 1)
                ])
        }
    }
    try project.validate()
    return project
}
```

Coordinates describe layer centers, with `(0, 0)` at the canvas's top-left. The image and text are separate clips, so either can be selected and edited by ID. For a repeatable SwiftUI-derived scene, pass IDs stored in your model to both `MediaTrack` and the clip factories.

## Commentary video and timed captions

This six-second composition uses a full-size video and a smaller commentary video in the upper-right corner. Background audio is muted, leaving the commentary's audio audible. Captions are ordinary text clips on the project timeline.

```swift
import Foundation
import SwiftVideo

struct CaptionCue: Identifiable, Sendable {
    let id: UUID
    let text: String
    let start: VideoTime
    let duration: VideoTime
}

func makeCommentary(footageURL: URL, commentaryURL: URL,
                    captions: [CaptionCue]) throws -> VideoProject {
    let six = try VideoTime(value: 6, timescale: 1)
    for caption in captions {
        let end = try caption.start.adding(caption.duration)
        guard caption.start >= .zero, caption.duration > .zero, end <= six else {
            throw VideoError.invalidProject("Captions must fit inside the six-second scene.")
        }
    }
    let project = VideoProject {
        MediaTrack("Footage") {
            MediaClip.video(footageURL, duration: six)
                .audio(AudioSettings(isMuted: true))
        }
        MediaTrack("Commentary") {
            MediaClip.video(commentaryURL, duration: six)
                .zIndex(1)
                .transform(VisualTransform(x: 0.8, y: 0.23,
                                           width: 0.32, height: 0.32,
                                           contentMode: .fill))
        }
        MediaTrack("Captions") {
            for caption in captions {
                MediaClip.text(caption.text, duration: caption.duration,
                               style: TextStyle(fontSize: 52,
                                                shadow: TextShadow(radius: 4)),
                               id: caption.id)
                    .starting(at: caption.start)
                    .zIndex(2)
                    .transform(VisualTransform(y: 0.88, width: 0.9, height: 0.18))
            }
        }
    }
    try project.validate()
    return project
}

func sampleCaptions() throws -> [CaptionCue] {
    let two = try VideoTime(value: 2, timescale: 1)
    let four = try VideoTime(value: 4, timescale: 1)
    return [
        CaptionCue(id: UUID(), text: "Here is the original scene.", start: .zero, duration: two),
        CaptionCue(id: UUID(), text: "Notice the change in perspective.", start: two, duration: two),
        CaptionCue(id: UUID(), text: "Now compare both views.", start: four, duration: two)
    ]
}
```

Create caption IDs once and retain them when updating their text or timing. This recipe positions captions but does not transcribe speech or parse subtitle files. For existing subtitles, convert their timestamps and text into `CaptionCue` values in your application.

## Visual and audio crossfade

Two four-second clips overlap for half a second, producing a 7.5-second project. The upper clip fades in visually while opposing audio fades blend their sound. There is no separate transition object.

```swift
import Foundation
import SwiftVideo

func makeCrossfade(firstURL: URL, secondURL: URL) throws -> VideoProject {
    let four = try VideoTime(value: 4, timescale: 1)
    let half = try VideoTime(value: 1, timescale: 2)
    let secondStart = try four.subtracting(half)
    let project = VideoProject {
        MediaTrack("Sequence") {
            MediaClip.video(firstURL, duration: four)
                .audio(AudioSettings(volume: 0.7, fadeOut: half))
            MediaClip.video(secondURL, duration: four)
                .starting(at: secondStart)
                .zIndex(1)
                .audio(AudioSettings(volume: 0.7, fadeIn: half))
                .animate(.opacity, keyframes: [
                    Keyframe(time: .zero, value: 0),
                    Keyframe(time: half, value: 1)
                ])
        }
    }
    try project.validate()
    return project
}
```

## Export a project

This helper writes a new MP4 with a unique name. It creates the containing directory because the exporter does not create parent directories.

```swift
import Foundation
import SwiftVideo

func exportComposition(_ project: VideoProject, directory: URL) async throws -> URL {
    try FileManager.default.createDirectory(at: directory,
                                            withIntermediateDirectories: true)
    let output = directory.appendingPathComponent("SwiftVideo-\(UUID()).mp4")
    return try await VideoExporter().export(
        project, to: output,
        settings: ExportSettings(resolution: .hd1080, frameRate: .fps30)
    )
}
```

Use the returned URL only after the function succeeds. A failed or cancelled export removes its staging file. Keep the input files readable until completion. A custom resolution changes encoded output size; the project canvas continues to define text sizing and normalized placement.

## Cancellable export from SwiftUI

Keep export state on `MainActor`, retain one exporter, and update progress from the `@Sendable` callback through a main-actor task. The operation ID prevents a delayed callback from an earlier export from changing a newer operation's state.

```swift
import Foundation
import Observation
import SwiftVideo

@MainActor
@Observable
final class CompositionExportModel {
    private(set) var isExporting = false
    private(set) var fraction = 0.0
    private(set) var outputURL: URL?
    private(set) var errorMessage: String?

    private let exporter = VideoExporter()
    private var activeID: UUID?

    func export(_ project: VideoProject, to destination: URL) async {
        guard !isExporting else { return }
        let id = UUID()
        activeID = id
        isExporting = true
        fraction = 0
        outputURL = nil
        errorMessage = nil
        defer {
            activeID = nil
            isExporting = false
        }
        do {
            outputURL = try await exporter.export(project, to: destination) { [weak self] update in
                Task { @MainActor [weak self] in
                    guard let self, self.activeID == id else { return }
                    self.fraction = max(self.fraction, update.fraction)
                }
            }
            fraction = 1
        } catch VideoError.cancelled {
            // Requested cancellation leaves outputURL nil.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancel() async {
        await exporter.cancel()
    }
}
```

Store the model in a SwiftUI view's `@State`. Start `await model.export(project, to: destination)` in a task from an Export button, and `await model.cancel()` from a Cancel button. Disable Export while `isExporting` is true. Create the destination directory first, retain source-file access, and use a unique output URL. Cancelling the task awaiting `export` also cancels rendering.

For previews, use a separate exporter at a lower resolution, debounce rapid edits, cancel superseded work, and discard stale results. Do not launch exports from `View.body`. The shared [example store](../Example/Sources/SwiftVideoEditor/EditorStore.swift) implements preview scheduling, snapshot history, and platform resource handling; use it when integrating with Skip/SwiftUIComponents.

## Next steps

Read [editing semantics](APIReference.md#editing) before adding timeline interactions and [persistence](Guide.md#save-and-restore-a-project) before saving projects. Check [platform limits](Guide.md#platform-architecture-and-limits) before choosing output formats, and use the [example editor](../Example/README.md) to see the recipes in a complete application.
