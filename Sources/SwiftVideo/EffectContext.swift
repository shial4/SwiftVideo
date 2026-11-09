// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

/// Render-time values in seconds. Editing continues to use exact `VideoTime` arithmetic.
public struct EffectContext: Sendable {
    public let projectTime: Double
    /// The original effect clock, including the portion removed by trimming or splitting.
    public let effectTime: Double
    public let effectDuration: Double
    public let sourceTime: Double
    public var progress: Double { min(1, max(0, effectTime / effectDuration)) }
}

/// Resolve clock coefficients once in Swift. The Android adapter only evaluates these mappings.
struct EffectClock: Encodable, Sendable {
    let effectOffset: Double
    let effectDuration: Double
    let sourceOffset: Double
    let sourceRate: Double

    init(clip: MediaClip) {
        effectOffset = clip.effectsOffset.seconds - clip.start.seconds
        effectDuration = clip.effectsDuration.seconds
        sourceRate = clip.playbackRate.multiplier
        sourceOffset = clip.sourceStart.seconds - clip.start.seconds * sourceRate
    }

    func context(at projectTime: Double) -> EffectContext {
        EffectContext(projectTime: projectTime, effectTime: projectTime + effectOffset,
                            effectDuration: effectDuration, sourceTime: projectTime * sourceRate + sourceOffset)
    }
}
