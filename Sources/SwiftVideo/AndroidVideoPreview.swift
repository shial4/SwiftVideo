// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import SwiftVideoMedia3

/// Native Swift owner of a direct Android preview. The platform surface adapter
/// attaches to `session`; project validation and animation stay in SwiftVideo.
public final class AndroidVideoPreview {
    public let session: Media3PreviewSession

    public init(project: VideoProject, settings: ExportSettings, effects: EffectRegistry = .empty) throws {
        let plan = try AndroidVideoRenderer.renderPlan(project, settings: settings, effects: effects)
        let prepared = try AndroidRenderEffects(project: project, plan: plan, registry: effects)
        session = Media3PreviewSession()
        try session.start(json: prepared.json, sample: AndroidRenderPlan.visualSampler(for: project),
            audio: { try prepared.audio(id: $0, sampleRate: $1, channels: $2, data: $3, reset: $4) },
            visual: { try prepared.visual(id: $0, index: $1) },
            titleMotion: { try prepared.titleMotion(id: $0, microseconds: $1) },
            seeked: { prepared.seek(to: Double($0) / 1000) }, released: { prepared.finish() })
    }

    // The bridge serializes release onto Android's application looper. This
    // immutable Swift owner does not require a Swift UI executor for cleanup.
    deinit { session.release() }
}
#endif
