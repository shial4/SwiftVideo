// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import SwiftVideoMedia3

/// Native Swift owner of a direct Android preview. The platform surface adapter
/// attaches to `session`; project validation and animation stay in SwiftVideo.
public final class AndroidVideoPreview {
    public let session: Media3PreviewSession

    public init(project: VideoProject, settings: ExportSettings) throws {
        guard try project.renderClips().allSatisfy({ $0.textMotion == nil }) else {
            throw VideoError.unsupportedFeature("Direct Android preview does not yet support motion titles.")
        }
        let json = try AndroidVideoRenderer.serializedPlan(project, settings: settings)
        session = Media3PreviewSession()
        try session.start(json: json, sample: AndroidRenderPlan.visualSampler(for: project))
    }

    // The bridge serializes release onto Android's application looper. This
    // immutable Swift owner does not require a Swift UI executor for cleanup.
    deinit { session.release() }
}
#endif
