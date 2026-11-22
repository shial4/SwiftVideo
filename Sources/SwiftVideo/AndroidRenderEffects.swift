// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import SwiftVideoMedia3

/// Immutable callbacks shared by export and preview. Audio state remains protected
/// by AndroidAudioEffects; Media3 owns each visual processor on its GL thread.
final class AndroidRenderEffects: Sendable {
    let json: String
    private let nativeEffects: [String: [Int: @Sendable () throws -> Media3VisualEffect]]
    private let audioEffects: [String: AndroidAudioEffects]
    private let titleClips: [String: (MediaClip, TextMotion, Int)]

    init(project: VideoProject, plan: AndroidRenderPlan, registry: EffectRegistry) throws {
        let encoded = try JSONEncoder().encode(plan)
        guard let json = String(data: encoded, encoding: .utf8) else {
            throw VideoError.invalidProject("Cannot serialize Android render plan.")
        }
        self.json = json
        nativeEffects = Dictionary(uniqueKeysWithValues: plan.clips.map { clip in
            (clip.id, Dictionary(uniqueKeysWithValues: clip.filters.enumerated().compactMap { index, filter in
                filter.nativeFactory.map { (index, $0) }
            }))
        })
        let clips = try project.renderClips()
        audioEffects = Dictionary(uniqueKeysWithValues: clips.filter { $0.audio.filters.contains(where: \.isCustom) }
            .map { ($0.id.uuidString, AndroidAudioEffects(clip: $0, registry: registry)) })
        titleClips = Dictionary(uniqueKeysWithValues: clips.compactMap { clip -> (String, (MediaClip, TextMotion, Int))? in
            guard case .text(let text, _) = clip.source, let motion = clip.textMotion else { return nil }
            return (clip.id.uuidString, (clip, motion, motion.ranges(in: text).count))
        })
    }

    func audio(id: String, sampleRate: Int, channels: Int, data: Data, reset: Bool) throws -> Data {
        guard let effect = audioEffects[id] else { throw VideoError.renderingFailed("A custom audio effect was not prepared.") }
        return try effect.process(data, sampleRate: sampleRate, channels: channels, reset: reset)
    }

    func visual(id: String, index: Int) throws -> Media3VisualEffect {
        guard let factory = nativeEffects[id]?[index] else {
            throw VideoError.renderingFailed("A native visual effect was not prepared.")
        }
        return try factory()
    }

    func titleMotion(id: String, microseconds: Double) throws -> Data {
        guard let (clip, motion, count) = titleClips[id] else { throw VideoError.renderingFailed("A motion title was not prepared.") }
        let time = try VideoTime(value: Int64(microseconds.rounded()), timescale: 1_000_000).subtracting(clip.start).adding(clip.effectsOffset)
        var values = [Float](repeating: 0, count: count * 5)
        for index in 0..<count {
            let t = try motion.transform(forUnit: index, at: time)
            values[index * 5] = Float(t.x); values[index * 5 + 1] = Float(t.y)
            values[index * 5 + 2] = Float(t.scale); values[index * 5 + 3] = Float(t.rotation)
            values[index * 5 + 4] = Float(t.opacity)
        }
        // Only transform scalars cross JNI; glyph pixels stay on the GPU.
        return values.withUnsafeBytes { Data($0) }
    }

    func seek(to projectTime: Double) { for effect in audioEffects.values { effect.seek(to: projectTime) } }
    func finish() { for effect in audioEffects.values { effect.finish() } }
    deinit { finish() }
}
#endif
