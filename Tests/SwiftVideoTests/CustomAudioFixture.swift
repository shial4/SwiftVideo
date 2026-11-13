// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(os)
import os
#else
import Synchronization
#endif
@testable import SwiftVideo

final class AudioEffectCounts: Sendable {
    struct State: Sendable {
        var created = 0, resets = 0, finished = 0
        var contexts: [EffectContext] = []
    }
    #if canImport(os)
    let state = OSAllocatedUnfairLock(initialState: State())
    #else
    let state = Mutex(State())
    #endif
}

enum CustomAudioFixture {
    static let id = EffectIdentifier("test.audio")
    enum Mode: Sendable { case gain, delay, offset, prepareFail, fail, resize, nonfinite }

    static func definition(mode: Mode = .gain, counts: AudioEffectCounts = AudioEffectCounts(),
                           onProcess: @escaping @Sendable () -> Void = {}) -> AudioEffectDefinition {
        AudioEffectDefinition(id, parameters: ["gain": EffectParameter(.number, defaultValue: .number(2), range: 0...4)]) { values, format in
            if case .prepareFail = mode { throw VideoError.renderingFailed("Test audio preparation failure") }
            counts.state.withLock { $0.created += 1 }
            guard case .number(let gain) = values["gain"] else { throw VideoError.invalidProject("Missing test gain.") }
            return Processor(mode: mode, counts: counts, gain: Float(gain), channels: format.channels, onProcess: onProcess)
        }
    }

    private struct Processor: AudioEffectProcessor {
        let mode: Mode
        let counts: AudioEffectCounts
        let gain: Float
        let channels: Int
        let onProcess: @Sendable () -> Void
        private var previous: [Float] = [0, 0]

        init(mode: Mode, counts: AudioEffectCounts, gain: Float, channels: Int, onProcess: @escaping @Sendable () -> Void) {
            self.mode = mode; self.counts = counts; self.gain = gain; self.channels = channels; self.onProcess = onProcess
        }

        mutating func process(_ samples: inout [Float], context: EffectContext) throws {
            counts.state.withLock { $0.contexts.append(context) }
            onProcess()
            switch mode {
            case .gain: for index in samples.indices { samples[index] *= gain }
            case .offset: for index in samples.indices { samples[index] += 0.25 }
            case .delay:
                for index in samples.indices {
                    let channel = index % channels, original = samples[index]
                    samples[index] = previous[channel]; previous[channel] = original
                }
            case .fail, .prepareFail: throw VideoError.renderingFailed("Test audio failure")
            case .resize: samples.append(0)
            case .nonfinite: if !samples.isEmpty { samples[0] = .nan }
            }
        }

        mutating func reset() { previous = [0, 0]; counts.state.withLock { $0.resets += 1 } }
        func finish() { counts.state.withLock { $0.finished += 1 } }
    }
}
