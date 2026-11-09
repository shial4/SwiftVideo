<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Custom visual effects

This API is under development on `codex/effect-extensibility`. It is not included in 0.0.1 or 0.0.2-beta.1. The first implementation supports app-defined GPU filters for video, images and rasterized text, on individual clips or every visual clip in a track.

## Register an effect

An effect has an exact identifier/version, a parameter schema and a factory for each supported platform. Registries are immutable values passed to an exporter. There is no global registration or automatic fallback to a different version.

This example rotates RGB channels. The same project and parameter values work in native Apple apps and shared Swift Skip Fuse apps.

```swift
import SwiftVideo
#if canImport(CoreImage)
import CoreImage
#endif

let channelRotation = EffectIdentifier("com.example.channel-rotation", version: 1)

func makeEffects() throws -> EffectRegistry {
    var effect = VisualEffectDefinition(channelRotation, parameters: [
        "amount": EffectParameter(.number, defaultValue: .number(1), range: 0...1)
    ]).android { values in
        guard case .number(let amount) = values["amount"] else {
            throw VideoError.invalidProject("Missing amount")
        }
        return AndroidVisualEffect(fragmentShader: """
            precision mediump float;
            uniform sampler2D uTexSampler;
            uniform float uAmount;
            varying vec2 vTexCoord;
            void main() {
                vec4 color = texture2D(uTexSampler, vTexCoord);
                gl_FragColor = vec4(mix(color.rgb, color.gbr, uAmount), color.a);
            }
            """, uniforms: ["uAmount": [Float(amount)]])
    }
    #if canImport(CoreImage)
    effect = effect.apple { values in
        guard case .number(let amount) = values["amount"] else {
            throw VideoError.invalidProject("Missing amount")
        }
        return ChannelRotation(amount: amount)
    }
    #endif
    return try EffectRegistry(visual: [effect])
}

#if canImport(CoreImage)
final class ChannelRotation: AppleVisualEffectProcessor {
    let amount: Double
    init(amount: Double) { self.amount = amount }

    func apply(to image: CIImage) throws -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - amount, y: amount, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 - amount, z: amount, w: 0),
            "inputBVector": CIVector(x: amount, y: 0, z: 1 - amount, w: 0)
        ])
    }
}
#endif
```

Factories receive validated parameters with defaults filled in. Supported values are `.number(Double)`, `.vector([Double])`, `.boolean(Bool)` and `.text(String)`. Vector schemas declare an exact size from 1 through 16. All numbers must be finite. Numeric ranges are inclusive and apply to every vector component. A parameter without a default is required; unknown parameters and type mismatches fail validation.

## Apply it to a clip or track

```swift
let reference = EffectReference(channelRotation, parameters: ["amount": .number(0.75)])
let clip = MediaClip.video(inputURL, duration: try VideoTime(value: 2, timescale: 1))
    .filter(.custom(reference))
let track = MediaTrack(clips: [clip]).filter(.saturation(0.8))
let project = VideoProject(tracks: [track])
let registry = try makeEffects()
let exporter = VideoExporter(effects: registry)
try await exporter.export(project, to: outputURL)
```

Filters run in authored order: clip filters first, then track filters. A track effect is instantiated separately for each visual clip; it is not a post-composition adjustment layer. Use `track.filter(.custom(reference))` to apply the effect to all its visual clips. Transform animations, layout, opacity and composition continue to use the existing clip API.

For SwiftUI, keep the registry with your export service and pass immutable project snapshots to the exporter. Parameter edits produce new `EffectReference` and project values. Apply the same debounce/cancellation policy as any other preview export. For native Kotlin consumers, register the effect in the native Swift wrapper before invoking the exporter; the [existing wrapper integration](Integration.md#native-android-and-kotlin) still applies.

## Save, restore and check support

`VideoProject` remains `Codable`. JSON contains effect IDs, exact versions and parameter values. Shader source and factories are not serialized. Only application code can register executable implementations; loading a project does not load a shader, download code or select a substitute effect.

`project.validate()` checks reference structure. `registry.validate(project, for: .android)` or `.apple` checks registered versions, parameter schemas and implementations before media I/O. `registry.supportedPlatforms(for: channelRotation)` reports the adapters present in that compiled registry. A conditional Apple factory is absent from an Android build. Renderer feature support is exposed as `.customVisualEffects`.

Keep older effect versions registered when restoring projects that use them. Increment the version when changing shader behavior, parameter meaning or defaults. Unknown versions and unsupported platforms fail with `VideoError.unsupportedFeature`; invalid parameter data fails with `VideoError.invalidProject`.

## GPU execution and lifetime

On Apple, the factory runs once per clip/filter/export. Return a fresh processor each time. Its synchronous methods run on the renderer's serial executor. Build a lazy Core Image graph, optionally using your own compiled Core Image Metal kernels. Preserve the input extent and premultiplied alpha. The renderer evaluates the graph through its shared Metal-backed `CIContext`; do not create another context or read pixels back to the CPU. Override `finish()` to release your resources. It is called once for every successfully prepared processor, including later preparation failures, render failures and cancellation.

On Android, the factory returns an OpenGL ES 2.0 fragment shader and float uniforms. Media3 compiles it once on the GL context's thread and releases its program and output textures when the export ends. Use `uTexSampler` for the input 2D texture and `vTexCoord` for normalized texture coordinates. Optional `uTexelSize` is a `vec2` containing reciprocal input width and height. User uniforms support float, vec2, vec3 and vec4 values and must match active uniforms in the shader. The two renderer-owned uniform names cannot be overridden. Preserve the input size and write straight-alpha RGBA: reducing opacity changes alpha without multiplying RGB. Media3's compositor multiplies the source RGB by alpha when blending. No pixel transfer through the Swift/Kotlin bridge is added.

The current contract is for spatial SDR filters with fixed per-export parameters. Time-varying shader parameters, additional texture inputs, custom audio processors, motion-title presets and segmentation are later milestones. Shader compilation and device GL limits can still cause export failure; the normal staging cleanup and destination protection apply. Emulator results verify behavior, not physical-device throughput or vendor GPU compatibility.
