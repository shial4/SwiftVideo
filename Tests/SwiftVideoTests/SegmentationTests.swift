// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo
@testable import SwiftVideoSegmentation

@Suite struct SegmentationTests {
    @Test func personFilterRoundTripsAndRequiresRegisteredImplementation() throws {
        let filter = PersonSegmentation.filter(threshold: 0.3, softness: 0.4)
        let clip = MediaClip.text("Person", duration: try VideoTime(value: 1, timescale: 5)).filter(filter)
        let project = VideoProject { MediaTrack(clips: [clip]) }
        let restored = try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project))
        #expect(restored.tracks[0].clips[0].filters == [filter])
        let definition = try PersonSegmentation.definition(appleModelURL: URL(fileURLWithPath: "/model.mlmodelc"),
                                                           androidModelURL: URL(fileURLWithPath: "/model.tflite"))
        let registry = try EffectRegistry(visual: [definition])
        #if os(Android)
        let platform = EffectPlatform.android
        #expect(throws: VideoError.self) { try PersonSegmentation.definition() }
        #else
        let platform = EffectPlatform.apple
        #if targetEnvironment(simulator)
        #expect(throws: VideoError.self) { try PersonSegmentation.definition() }
        #endif
        #endif
        try registry.validate(restored, for: platform)
        #expect(throws: VideoError.self) { try EffectRegistry.empty.validate(restored, for: platform) }
    }

    @Test func segmentationSettingsRejectInvalidConfidenceRanges() throws {
        let valid = try SegmentationSettings(["threshold": .number(0.4), "softness": .number(0.2)])
        #expect(valid.threshold == 0.4 && valid.softness == 0.2)
        for pair in [(0.9, 0.2), (-0.1, 0.2), (0.4, -0.1), (Double.nan, 0.1), (0.1, Double.infinity)] {
            #expect(throws: VideoError.self) {
                try SegmentationSettings(["threshold": .number(pair.0), "softness": .number(pair.1)])
            }
        }
        #expect(throws: VideoError.self) { try SegmentationSettings([:]) }
    }

    #if os(Android)
    @Test func androidPlansValidateConfidenceBeforeOpeningTheModel() throws {
        for compute in [PersonSegmentation.AndroidCompute.gpu, .cpu] {
            let registry = try EffectRegistry(visual: [PersonSegmentation.definition(
                androidModelURL: URL(fileURLWithPath: "/not-opened-during-planning.tflite"), androidCompute: compute)])
            let clip = MediaClip.text("Person", duration: try VideoTime(value: 1, timescale: 5))
            let valid = VideoProject { MediaTrack(clips: [clip]).filter(PersonSegmentation.filter()) }
            let plan = try AndroidRenderPlan(project: valid, settings: ExportSettings(), effects: registry)
            #expect(plan.clips[0].filters[0].kind == "native")
            let invalid = VideoProject { MediaTrack(clips: [clip]).filter(PersonSegmentation.filter(threshold: 0.9, softness: 0.2)) }
            #expect(throws: VideoError.self) { try AndroidRenderPlan(project: invalid, settings: ExportSettings(), effects: registry) }
        }
        #expect(throws: VideoError.self) {
            try PersonSegmentation.definition(androidModelURL: URL(string: "https://example.com/model.tflite"))
        }
    }
    #endif
}
