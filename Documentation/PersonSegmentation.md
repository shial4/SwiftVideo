<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Person background removal

Unreleased work on `codex/effect-extensibility`. This API is not in stable 0.0.1, the 0.0.2 betas, or `main`.

The optional `SwiftVideoSegmentation` product removes the background behind people in images and video. It registers an ordinary [custom visual effect](CustomEffects.md), so it works on clips or tracks, combines with existing filters, and saves a versioned reference and parameters in project JSON. It does not identify arbitrary foreground objects or produce a studio-quality hair matte.

## Add the optional product

For development against this branch, add both products to your app target:

```swift
.package(url: "https://github.com/shial4/SwiftVideo.git",
         branch: "codex/effect-extensibility")

// Target dependencies:
.product(name: "SwiftVideo", package: "SwiftVideo"),
.product(name: "SwiftVideoSegmentation", package: "SwiftVideo")
```

The normal `SwiftVideo` product has no MediaPipe dependency or model resources. The optional Android product links MediaPipe Tasks Vision/Core 1.2.2. Your application supplies local model files; the library never downloads models. Kotlin callers can keep this configuration inside their [native Swift wrapper](Integration.md#native-android-and-kotlin).

## Export a cutout over a background

```swift
import SwiftVideo
import SwiftVideoSegmentation

func exportPerson(image: URL, appleModel: URL?, androidModel: URL?, output: URL) async throws {
    let registry = try EffectRegistry(visual: [
        PersonSegmentation.definition(appleModelURL: appleModel,
                                      androidModelURL: androidModel)
    ])
    let duration = try VideoTime(value: 3, timescale: 1)
    let project = VideoProject(canvas: VideoSize(width: 1280, height: 720),
                               background: VideoColor(red: 0.1, green: 0.2, blue: 0.4)) {
        MediaTrack(clips: [MediaClip.image(image, duration: duration)])
            .filter(PersonSegmentation.filter(threshold: 0.4, softness: 0.2))
    }
    try await VideoExporter(effects: registry).export(project, to: output)
}
```

Use `MediaClip.video` for footage. Put another image or video below the cutout for background replacement. Existing source alpha is preserved. Filters execute in authored order, before clip crop and placement. The model and inference settings belong to the effect registry; JSON contains neither model bytes nor machine-specific paths. Register the same identifier when reopening a project.

`threshold` and `softness` must be finite values in `0...1`, with a sum no greater than 1. The mask smoothly transitions between `threshold` and `threshold + softness`. A zero softness gives a hard edge. DeepLab emits class labels rather than probabilities, so these controls affect interpolation at mask edges, not the model's classification confidence.

## Models and compute behavior

| Environment | Model | Execution |
| --- | --- | --- |
| Apple device or macOS, no model URL | System Vision person segmentation | Balanced quality; Vision selects supported compute devices. Core Image scales and composites the mask on Metal. |
| Apple, explicit model URL | Apple's published DeepLabV3 / DeepLabV3FP16 Core ML model | Core ML selects available CPU, GPU and Neural Engine work. Metal selects the person class and Core Image composites. Works in the iOS Simulator. |
| Android, default | MediaPipe Selfie Segmenter, square float16 version 1 | GPU inference. A model or GPU-driver failure is reported; it does not silently switch to CPU. |
| Android, explicit `androidCompute: .cpu` | Same Selfie Segmenter model | CPU inference for unsupported GPU environments. Scaling, color conversion, mask interpolation and compositing still use OpenGL. |

Apple Vision's built-in segmentation does not work in the tested iOS Simulators. Balanced/accurate modes report `E5RT is not supported`; the fast CPU path returns an empty mask. Calling `definition()` there fails explicitly. Supply `appleModelURL` to use real segmentation in the simulator. Mac tests exercise both Vision and Core ML; simulator tests use Core ML.

For Core ML, prefer an Xcode-compiled `.mlmodelc` directory. A local raw `.mlmodel` file also works, but compiles once per effect processor; a track with several clips therefore repeats that preparation. Temporary compilations are removed on completion or failure. Pass the compiled resource URL from your app bundle to avoid runtime compilation. The adapter requires `image` at 513x513 and `semanticPredictions` as a 513x513 Int32 class map, with person class 15. [Apple's model catalogue](https://developer.apple.com/machine-learning/models/) supplies DeepLabV3 variants. Other model architectures are not accepted by this adapter.

Android requires the [square Selfie Segmenter model](https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/1/selfie_segmenter.tflite), supplied as a readable local file of at most 16 MB. APK assets must first be copied to app-private storage. The landscape model and arbitrary segmentation models are not supported. Follow the [model card](https://storage.googleapis.com/mediapipe-assets/Model%20Card%20MediaPipe%20Selfie%20Segmentation.pdf) for intended use and limitations.

The tested Android emulator's GL translator rejects the shader-storage-buffer query used by the MediaPipe GPU delegate. Select `androidCompute: .cpu` explicitly for that environment. Emulator tests validate real inference and the production GL compositor with this setting. GPU-delegate inference on physical Android devices remains unverified.

## Performance and verification

Inference runs off the main actor on the export executor. Input resizing and color conversion remain on the GPU. Android's public MediaPipe API requires a bounded 256x256 RGBA input buffer and confidence-mask upload even with GPU inference. Core ML exposes a 513x513 integer map; the adapter copies roughly 1 MB per frame to a reusable Metal buffer, then selects class 15 on the GPU. Neither path iterates over full-resolution video pixels on the CPU.

These are per-frame models, not motion-aware video matting. Hair, transparency, motion blur, occlusion, distant people and scene changes can produce errors or flicker. Results differ across models and platforms. There is no real-time throughput guarantee. Inference calls finish before cancellation can release their resources; the export still checks cancellation between stages and cleans staging files.

Integration tests render six 320x180 frames, decode independent pixels to verify the retained person and removed background, and check corrupt/missing-model failure followed by recovery. The video test first encodes a portrait, then segments decoded video. [Fixture provenance](../Tests/SwiftVideoTests/SegmentationFixtures.md) records model versions, checksums, notices and the original generated portrait. This controlled fixture is not a model-quality benchmark. [Tests and coverage](Testing.md) describes the separate optional-module measurements.

A November 10 diagnostic used a native SwiftPM Debug consumer at commit `20331d4`, an Apple M3 running macOS 26.6.2, and ten sequential 0.2-second image clips at 320x180/30 fps. With a precompiled DeepLabV3FP16 model, export plus independent pixel/duration verification took 1.66 seconds and peak resident memory was 168 MiB. The raw-model run took 11.36 seconds and 220 MiB. A one-clip precompiled run used 56 MiB. These are single local observations, not a sustained or cross-device benchmark; concurrent work and model caches affect timings. Each clip owns its processor and model resources, so memory grows with clip count. Use compiled models and representative project sizes when measuring your app.

An independent native Kotlin consumer also packaged the optional product into AARs, exported three sequential segmented clips on API 35, checked pixels in every clip, and recovered after a missing-model error. It selected CPU inference explicitly for the emulator; this does not verify the physical-device GPU delegate.

Retain the model's and runtime's applicable [third-party notices](ThirdParty/README.md) in your app. No model is bundled in the library product.
