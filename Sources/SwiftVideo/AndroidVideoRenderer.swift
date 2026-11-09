// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import SwiftVideoMedia3

/// Media3 owns native Android codecs. The bridge is authored entirely in Swift.
public actor AndroidVideoRenderer: VideoRendering {
    public nonisolated let capabilities = RendererCapabilities(name: "Media3 Transformer",
        features: Set(CompositionFeature.allCases), codecs: [.h264, .hevc], containers: [.mp4])

    private let effects: EffectRegistry
    public init(effects: EffectRegistry = .empty) { self.effects = effects }

    public func render(_ project: VideoProject, to destination: URL, settings: ExportSettings,
                       progress: @escaping @Sendable (ExportProgress) -> Void) async throws {
        try project.validate()
        try settings.validate(for: project)
        try capabilities.validate(project, settings: settings)
        try effects.validate(project, for: .android)
        let rate = settings.frameRate ?? project.frameRate
        guard rate.denominator == 1 else {
            throw VideoError.unsupportedFeature("Media3 image-sequence frame timing currently requires an integer frame rate.")
        }
        let size = settings.resolution ?? project.canvas
        guard size.width <= 8192, size.height <= 8192, rate.framesPerSecond <= 240 else {
            throw VideoError.unsupportedFeature("This renderer supports output up to 8192 pixels per dimension and 240 fps.")
        }
        let plan = try AndroidRenderPlan(project: project, settings: settings, effects: effects)
        let nativeEffects = Dictionary(uniqueKeysWithValues: plan.clips.map { clip in
            (clip.id, Dictionary(uniqueKeysWithValues: clip.filters.enumerated().compactMap { index, filter in
                filter.nativeFactory.map { (index, $0) }
            }))
        })
        let encoded = try JSONEncoder().encode(plan)
        guard let json = String(data: encoded, encoding: .utf8) else { throw VideoError.invalidProject("Cannot serialize Android render plan.") }
        let clips = Dictionary(uniqueKeysWithValues: try project.renderClips().map { ($0.id.uuidString, $0) })
        let session = try Media3ExportSession()
        let audioEffects = Dictionary(uniqueKeysWithValues: clips.values
            .filter { $0.audio.filters.contains(where: \.isCustom) }
            .map { ($0.id.uuidString, AndroidAudioEffects(clip: $0, registry: effects)) })
        let titleClips = Dictionary(uniqueKeysWithValues: clips.values.compactMap { clip -> (String, (MediaClip, TextMotion, Int))? in
            guard case .text(let text, _) = clip.source, let motion = clip.textMotion else { return nil }
            return (clip.id.uuidString, (clip, motion, motion.ranges(in: text).count))
        })
        defer { for effect in audioEffects.values { effect.finish() } }
        progress(ExportProgress(phase: .preparing, fraction: 0))
        try session.start(json: json, outputPath: destination.path, sample: { id, microseconds in
            guard let clip = clips[id], let time = try? VideoTime(value: Int64(microseconds.rounded()), timescale: 1_000_000),
                  (try? clip.timeRange.contains(time)) == true,
                  let transform = try? clip.visualTransform(at: time) else { return [0.5, 0.5, 1, 0, 0] }
            return [transform.x, transform.y, transform.scale, transform.rotation, transform.opacity]
        }, audio: { id, sampleRate, channels, data, reset in
            guard let effect = audioEffects[id] else { throw VideoError.renderingFailed("A custom audio effect was not prepared.") }
            return try effect.process(data, sampleRate: sampleRate, channels: channels, reset: reset)
        }, visual: { id, index in
            guard let factory = nativeEffects[id]?[index] else {
                throw VideoError.renderingFailed("A native visual effect was not prepared.")
            }
            return try factory()
        }, titleMotion: { id, microseconds in
            guard let (clip, motion, count) = titleClips[id] else { throw VideoError.renderingFailed("A motion title was not prepared.") }
            let time = try VideoTime(value: Int64(microseconds.rounded()), timescale: 1_000_000).subtracting(clip.start).adding(clip.effectsOffset)
            var values = [Float](repeating: 0, count: count * 5)
            for index in 0..<count {
                let t = try motion.transform(forUnit: index, at: time)
                values[index * 5] = Float(t.x); values[index * 5 + 1] = Float(t.y)
                values[index * 5 + 2] = Float(t.scale); values[index * 5 + 3] = Float(t.rotation)
                values[index * 5 + 4] = Float(t.opacity)
            }
            // Only transform scalars cross JNI once per frame; glyph pixels stay on the GPU.
            return values.withUnsafeBytes { Data($0) }
        })
        do {
            while true {
                try Task.checkCancellation()
                let status = try session.currentStatus()
                if status == 2 { break }
                if status < 0 { throw VideoError.renderingFailed(try session.failureMessage()) }
                progress(ExportProgress(phase: .rendering, fraction: 0.95 * (try session.currentProgress())))
                try await Task.sleep(for: .milliseconds(100))
            }
            progress(ExportProgress(phase: .finishing, fraction: 0.95))
        } catch {
            try session.cancel()
            // Cancellation is queued on Media3's application looper. Wait for release
            // before the facade removes staging files.
            // An unstructured task does not inherit cancellation. Its suspension
            // remains effective even when the export's caller has been cancelled.
            try await Task {
                while try session.currentStatus() >= 0 && session.currentStatus() < 2 {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }.value
            throw error
        }
    }
}

extension VideoExporter {
    public init(effects: EffectRegistry = .empty) { self.init(renderer: AndroidVideoRenderer(effects: effects)) }
}
#endif
