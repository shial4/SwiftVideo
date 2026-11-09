<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Custom audio effects

This API is under development on `codex/effect-extensibility`. It is not included in 0.0.1 or 0.0.2-beta.1.

Write a Swift `AudioEffectProcessor` and register its factory with an `EffectRegistry`. The same implementation runs in native Apple applications and Skip Fuse applications on Android. Projects save an exact identifier/version and typed parameters, using the [same registration rules as visual effects](CustomEffects.md). They never contain executable code.

## Soft clipping and echo

The following complete example defines two app-owned effects. The echo keeps a bounded interleaved delay line; neither processor allocates an array inside its processing loop.

```swift
import SwiftVideo

let softClipID = EffectIdentifier("com.example.soft-clip", version: 1)
let echoID = EffectIdentifier("com.example.echo", version: 1)

struct SoftClip: AudioEffectProcessor {
    let drive: Float

    func process(_ samples: inout [Float], context: EffectContext) {
        for index in samples.indices {
            let value = samples[index] * drive
            samples[index] = value / (1 + abs(value))
        }
    }
}

struct Echo: AudioEffectProcessor {
    private var delay: [Float]
    private var cursor = 0
    let mix: Float
    let feedback: Float

    init(format: AudioEffectFormat, seconds: Double, mix: Float, feedback: Float) {
        let frames = max(1, Int((Double(format.sampleRate) * seconds).rounded()))
        delay = [Float](repeating: 0, count: frames * format.channels)
        self.mix = mix; self.feedback = feedback
    }

    mutating func process(_ samples: inout [Float], context: EffectContext) {
        for index in samples.indices {
            let dry = samples[index], delayed = delay[cursor]
            delay[cursor] = dry + delayed * feedback
            samples[index] = dry * (1 - mix) + delayed * mix
            cursor = (cursor + 1) % delay.count
        }
    }

    mutating func reset() {
        for index in delay.indices { delay[index] = 0 }
        cursor = 0
    }
}

func audioEffects() throws -> EffectRegistry {
    try EffectRegistry(audio: [
        AudioEffectDefinition(softClipID, parameters: [
            "drive": EffectParameter(.number, defaultValue: .number(2), range: 1...8)
        ]) { values, _ in
            guard case .number(let drive) = values["drive"] else {
                throw VideoError.invalidProject("Missing drive")
            }
            return SoftClip(drive: Float(drive))
        },
        AudioEffectDefinition(echoID, parameters: [
            "seconds": EffectParameter(.number, defaultValue: .number(0.12), range: 0.01...1),
            "mix": EffectParameter(.number, defaultValue: .number(0.25), range: 0...1),
            "feedback": EffectParameter(.number, defaultValue: .number(0.3), range: 0...0.95)
        ]) { values, format in
            guard case .number(let seconds) = values["seconds"],
                  case .number(let mix) = values["mix"],
                  case .number(let feedback) = values["feedback"] else {
                throw VideoError.invalidProject("Missing echo parameters")
            }
            return Echo(format: format, seconds: seconds, mix: Float(mix), feedback: Float(feedback))
        }
    ])
}
```

Apply the effects to a clip or every audio-bearing clip in a track. Clip filters run first, followed by track filters, in the order written:

```swift
let narration = MediaClip.audio(narrationURL, duration: duration)
    .audio(AudioSettings(filters: [
        .highPass(cutoffHz: 80),
        .custom(EffectReference(softClipID, parameters: ["drive": .number(1.5)]))
    ]))
let track = MediaTrack(clips: [narration])
    .audioFilter(.custom(EffectReference(echoID)))
let project = VideoProject(tracks: [track])
let exporter = VideoExporter(effects: try audioEffects())
try await exporter.export(project, to: outputURL)
```

Keep the registry in your application's composition service and pass it to every preview/export exporter. SwiftUI views can store and edit `EffectReference` values. Native Kotlin callers use their app's existing Skip bridge wrapper around that service; registration and DSP stay in compiled Swift. See [platform integration](Integration.md).

## Processing contract

- The factory receives resolved parameters and the actual `AudioEffectFormat`. Buffers contain interleaved Float32 PCM: mono, or alternating left/right stereo samples. Apple processes 48 kHz stereo; Android supplies the decoded processing format. Use the supplied format for delay lengths and frequency calculations.
- `process(_:context:)` runs after playback-speed processing and before gain, pan, fades, and mixing. Its context describes the first frame. For frame `n`, project/effect time advances by `Double(n) / Double(format.sampleRate)`. Source time also includes the combined clip/track playback rate. See [effect clocks](CustomEffects.md#animate-an-effect).
- Preserve the buffer's sample count and return finite values. A thrown error, changed sample count, or NaN/infinity fails the export and triggers normal staging cleanup. Output may exceed full scale temporarily, but final mixing limits the signal; leave headroom to avoid clipping.
- Factories return a fresh processor for each clip/filter/export. Calls on one processor are serial. `AudioEffectProcessor` is `Sendable` because Android may invoke a processor on different threads over its lifetime; value types with owned state are the simplest implementation.
- `reset()` runs before the first buffer and after stream flush/seek. Clear history while retaining configuration. A format change finishes the old processor and creates a new one. `finish()` runs once for every successfully created processor, including later factory failure, export failure, and cancellation. Both methods have empty defaults.
- Trim, split, a new preview, and a new export start with fresh DSP history. Their effect clock still preserves the authored time. Prior source audio is not replayed to warm delay lines. Track filters create separate per-clip processors; they are not effects on the mixed track output.
- Processors are one-in/one-out and cannot change duration or declare latency. Echo and reverb tails end with the clip. Extend the authored source/timeline if a tail must remain audible. Arbitrary resampling, extra output frames, surround audio, and bus effects are outside this contract.

Custom audio runs on the CPU in buffers. Stateful sample processing and small PCM blocks do not benefit from uploading each block to the GPU. Android crosses the Swift/JNI boundary once per block using byte arrays, rather than once per sample. Visual effects continue to use the GPU.

Chains containing custom audio use the shared Swift DSP path, including their built-in EQ stages. EQ-only chains retain AVAudioEngine on Apple and Media3's native JVM processor on Android. The shared EQ follows the same Audio EQ Cookbook response used by the Android renderer; Apple AVAudioUnitEQ can have a slightly different response. Tests cover channel isolation, reset, filter order, retiming, encoded output, invalid buffers, and cancellation on simulator/emulator.
