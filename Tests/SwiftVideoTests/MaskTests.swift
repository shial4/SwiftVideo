// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct MaskTests {
    @Test func clipAndTrackMasksRoundTripAndRetainTheirOrder() throws {
        let mask = MediaFilter.mask(VideoMask(shape: .rectangle, bounds: VideoCrop(x: 0.1, y: 0.2, width: 0.8, height: 0.6), feather: 0.2, inverted: true))
        let key = MediaFilter.chromaKey(ChromaKey(color: VideoColor(red: 0, green: 0, blue: 1), tolerance: 0.2, softness: 0.3))
        let clip = MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1)).filter(key)
        let project = VideoProject(tracks: [MediaTrack(clips: [clip]).filter(mask)])

        let decoded = try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project))

        #expect(decoded == project)
        try decoded.validate()
        #expect(try decoded.renderClips()[0].filters == [key, mask])
        let plan = try AndroidRenderPlan(project: decoded, settings: ExportSettings())
        #expect(plan.clips[0].filters.count == 2)
        for filter in plan.clips[0].filters { try #require(filter.shader).validate() }
    }

    @Test func invalidMasksAndKeysFailForDeserializedInputAsWellAsInitializers() throws {
        let invalid: [MediaFilter] = [
            .mask(VideoMask(bounds: VideoCrop(x: 0.5, width: 0.6))), .mask(VideoMask(bounds: VideoCrop(height: 0))),
            .mask(VideoMask(bounds: VideoCrop(y: -0.1))), .mask(VideoMask(feather: .nan)), .mask(VideoMask(feather: 0.51)),
            .chromaKey(ChromaKey(color: .clear)), .chromaKey(ChromaKey(tolerance: -0.1)),
            .chromaKey(ChromaKey(tolerance: 0.8, softness: 0.3)), .chromaKey(ChromaKey(softness: .infinity)),
            .chromaKey(ChromaKey(color: VideoColor(red: 1.1, green: 0, blue: 0)))
        ]
        for filter in invalid {
            let project = VideoProject(tracks: [MediaTrack(filters: [filter])])
            #expect(throws: VideoError.self) { try project.validate() }
        }
        let data = Data("{\"shape\":\"ellipse\",\"bounds\":{\"x\":0,\"y\":0,\"width\":1,\"height\":1},\"feather\":-1,\"inverted\":false}".utf8)
        #expect(throws: VideoError.self) { try JSONDecoder().decode(VideoMask.self, from: data).validate() }
        try VideoMask(shape: .ellipse, feather: 0.5).validate()
        try ChromaKey(tolerance: 1, softness: 0).validate()
        try ChromaKey(tolerance: 0, softness: 1).validate()
    }

    @Test(arguments: [MediaFilter.mask(VideoMask()), .chromaKey(ChromaKey())])
    func renderersMustDeclareTheSpecificMaskCapability(filter: MediaFilter) throws {
        let project = VideoProject(tracks: [MediaTrack(clips: [MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1))]).filter(filter)])
        let unsupported = RendererCapabilities(name: "Other renderer", features: [.text, .filters], codecs: [.h264], containers: [.mp4])
        #expect(throws: VideoError.self) { try unsupported.validate(project, settings: ExportSettings()) }
        let supported = RendererCapabilities(name: "Mask renderer", features: [.text, .filters, .masks, .chromaKey], codecs: [.h264], containers: [.mp4])
        try supported.validate(project, settings: ExportSettings())
    }
}
