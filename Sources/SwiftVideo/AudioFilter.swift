// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Ordered, per-clip audio processing, before gain, pan, fades, and mixing.
public enum AudioFilter: Hashable, Codable, Sendable {
    case lowPass(cutoffHz: Double)
    case highPass(cutoffHz: Double)
    case parametricEQ(frequencyHz: Double, gainDB: Double, bandwidthOctaves: Double)
    case custom(EffectReference)

    var isCustom: Bool { if case .custom = self { return true }; return false }

    /// Renderers also check against the decoded source's Nyquist frequency.
    func validate(sampleRate: Double? = nil) throws {
        let frequency: Double
        switch self {
        case .custom(let reference): try reference.validate(); return
        case .lowPass(let cutoff), .highPass(let cutoff): frequency = cutoff
        case .parametricEQ(let center, let gain, let bandwidth):
            frequency = center
            guard gain.isFinite, (-24...24).contains(gain), bandwidth.isFinite, (0.05...5).contains(bandwidth) else {
                throw VideoError.invalidProject("EQ gain must be -24...24 dB and bandwidth 0.05...5 octaves.")
            }
        }
        guard frequency.isFinite, frequency >= 20, frequency < (sampleRate ?? 48_000) / 2 else {
            throw VideoError.invalidProject("Audio filter frequency must be at least 20 Hz and below the source and processing Nyquist frequencies.")
        }
    }
}
