// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import Synchronization

/// Serializes synchronous Media3 buffer callbacks with exporter cleanup.
/// Native buffers cross JNI once per block as bytes, without boxing each Float.
final class AndroidAudioEffects: Sendable {
    private struct State: Sendable {
        var format: AudioEffectFormat?
        var chain: AudioEffectChain?
        var samples: [Float] = []
        var finished = false
    }
    private let state = Mutex(State())
    private let clip: MediaClip
    private let registry: EffectRegistry

    init(clip: MediaClip, registry: EffectRegistry) { self.clip = clip; self.registry = registry }

    func process(_ data: Data, sampleRate: Int, channels: Int, reset: Bool) throws -> Data {
        try state.withLock { state in
            guard !state.finished else { throw VideoError.renderingFailed("The audio effect has already finished.") }
            let format = try AudioEffectFormat(sampleRate: sampleRate, channels: channels)
            if state.format != format {
                state.chain?.finish(); state.chain = nil
                state.chain = try AudioEffectChain(clip: clip, registry: registry, platform: .android, format: format)
                state.format = format
            } else if reset { state.chain?.reset() }
            guard !data.isEmpty else { return Data() }
            guard data.count % (channels * MemoryLayout<Float>.size) == 0 else {
                throw VideoError.renderingFailed("Custom audio received incomplete PCM frames.")
            }
            let count = data.count / MemoryLayout<Float>.size
            if state.samples.count != count { state.samples = [Float](repeating: 0, count: count) }
            _ = state.samples.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            try state.chain?.process(&state.samples)
            return state.samples.withUnsafeBytes { Data($0) }
        }
    }

    func finish() {
        state.withLock { state in
            state.chain?.finish(); state.chain = nil; state.samples = []; state.finished = true
        }
    }
}
#endif
