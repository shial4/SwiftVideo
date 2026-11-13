// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Interleaved Float32 PCM. Stereo is left, right; mono contains one sample per frame.
public struct AudioEffectFormat: Equatable, Sendable {
    public let sampleRate: Int
    public let channels: Int

    public init(sampleRate: Int, channels: Int) throws {
        guard sampleRate > 0, (1...2).contains(channels) else {
            throw VideoError.unsupportedFeature("Custom audio effects require a positive sample rate and mono or stereo PCM.")
        }
        self.sampleRate = sampleRate; self.channels = channels
    }
}

/// One instance per clip/filter/export. Calls are serial and may run on different threads.
/// Prefer a value type. Preserve sample count, return finite PCM, and keep state bounded.
public protocol AudioEffectProcessor: Sendable {
    /// The context describes the first frame in the buffer, after playback speed processing.
    mutating func process(_ samples: inout [Float], context: EffectContext) throws
    /// Clear delay lines and other history before a new stream or seek. Configuration stays intact.
    mutating func reset()
    /// Release resources after success, failure, cancellation, or a format change.
    mutating func finish()
}

extension AudioEffectProcessor {
    public mutating func reset() {}
    public mutating func finish() {}
}

/// A portable Swift PCM implementation, registered explicitly by the application.
public struct AudioEffectDefinition: Sendable {
    public let id: EffectIdentifier
    public let parameters: [String: EffectParameter]
    public let supportedPlatforms: Set<EffectPlatform>
    let factory: @Sendable ([String: EffectValue], AudioEffectFormat) throws -> any AudioEffectProcessor

    public init(_ id: EffectIdentifier, parameters: [String: EffectParameter] = [:],
                platforms: Set<EffectPlatform> = Set(EffectPlatform.allCases),
                makeProcessor: @escaping @Sendable ([String: EffectValue], AudioEffectFormat) throws -> any AudioEffectProcessor) {
        self.id = id; self.parameters = parameters; supportedPlatforms = platforms; factory = makeProcessor
    }
}

/// Owns ordered native PCM stages only when the clip uses custom audio.
/// EQ-only clips retain the established AVAudioEngine and Media3 paths.
struct AudioEffectChain: Sendable {
    private var processors: [any AudioEffectProcessor] = []
    private let format: AudioEffectFormat
    private let clock: EffectClock
    private let start: Double
    private var frames: Int64 = 0

    init(clip: MediaClip, registry: EffectRegistry, platform: EffectPlatform, format: AudioEffectFormat) throws {
        self.format = format; clock = EffectClock(clip: clip); start = clip.start.seconds
        do {
            for filter in clip.audio.filters {
                try filter.validate(sampleRate: Double(min(48_000, format.sampleRate)))
                if case .custom(let reference) = filter {
                    let (definition, parameters) = try registry.resolveAudio(reference, for: platform)
                    processors.append(try definition.factory(parameters, format))
                } else { processors.append(try AudioBiquad(filter: filter, format: format)) }
            }
            reset()
        } catch { finish(); throw error }
    }

    mutating func process(_ samples: inout [Float]) throws {
        guard samples.count % format.channels == 0 else {
            throw VideoError.renderingFailed("Audio effects require complete PCM frames.")
        }
        let count = samples.count
        let context = clock.context(at: start + Double(frames) / Double(format.sampleRate))
        for index in processors.indices {
            try processors[index].process(&samples, context: context)
            guard samples.count == count, samples.allSatisfy(\.isFinite) else {
                throw VideoError.renderingFailed("An audio effect changed the sample count or returned non-finite PCM.")
            }
        }
        frames += Int64(count / format.channels)
    }

    mutating func reset() {
        frames = 0
        for index in processors.indices { processors[index].reset() }
    }

    mutating func finish() {
        for index in processors.indices { processors[index].finish() }
        processors.removeAll()
    }
}

/// W3C Audio EQ Cookbook coefficients, matching the existing Media3 EQ contract.
/// Used for ordered mixed custom/EQ chains; no JNI call occurs inside the sample loop.
private struct AudioBiquad: AudioEffectProcessor {
    let b0: Double, b1: Double, b2: Double, a1: Double, a2: Double
    let channels: Int
    var z1 = [Double](repeating: 0, count: 2)
    var z2 = [Double](repeating: 0, count: 2)

    init(filter: AudioFilter, format: AudioEffectFormat) throws {
        channels = format.channels
        let frequency: Double
        switch filter {
        case .lowPass(let value), .highPass(let value): frequency = value
        case .parametricEQ(let value, _, _): frequency = value
        case .custom: throw VideoError.invalidProject("A custom audio effect requires its registered factory.")
        }
        let omega = 2 * Double.pi * frequency / Double(format.sampleRate)
        let sine = sin(omega), cosine = cos(omega)
        if case .parametricEQ(_, let gain, let bandwidth) = filter {
            let amplitude = pow(10, gain / 40)
            let alpha = sine * sinh(log(2) / 2 * bandwidth * omega / sine)
            let inverse = alpha.isFinite ? 1 / alpha : 0
            let a0 = inverse + 1 / amplitude
            b0 = (inverse + amplitude) / a0; b1 = -2 * cosine * inverse / a0
            b2 = (inverse - amplitude) / a0; a1 = b1; a2 = (inverse - 1 / amplitude) / a0
        } else {
            let alpha = sine / sqrt(2), a0 = 1 + alpha
            if case .lowPass = filter {
                b0 = (1 - cosine) / (2 * a0); b1 = (1 - cosine) / a0
            } else { b0 = (1 + cosine) / (2 * a0); b1 = -(1 + cosine) / a0 }
            b2 = b0; a1 = -2 * cosine / a0; a2 = (1 - alpha) / a0
        }
    }

    mutating func process(_ samples: inout [Float], context: EffectContext) {
        for index in samples.indices {
            let channel = index % channels, input = Double(samples[index])
            let output = b0 * input + z1[channel]
            z1[channel] = b1 * input - a1 * output + z2[channel]
            z2[channel] = b2 * input - a2 * output
            samples[index] = Float(output)
        }
    }

    mutating func reset() { z1 = [0, 0]; z2 = [0, 0] }
}
