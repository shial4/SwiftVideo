// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
import SwiftVideo
import SwiftVideoSegmentation
#if os(Android)
import SwiftVideoTestSupport
#endif

extension RenderBehaviorTests {
    @Test(arguments: [false, true]) func personSegmentationRetainsThePersonAndRemovesTheBackground(video: Bool) async throws {
        try await checkPersonSegmentation(video: video, useVision: false)
    }

    #if os(macOS)
    @Test(arguments: [false, true]) func visionSegmentationRetainsThePersonAndRemovesTheBackground(video: Bool) async throws {
        try await checkPersonSegmentation(video: video, useVision: true)
    }
    #endif

    private func checkPersonSegmentation(video: Bool, useVision: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("person-mask-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let portrait = try segmentationFixture("person", extension: "png", folder: folder)
        let model = try segmentationModel(folder: folder)
        let duration = try VideoTime(value: 1, timescale: 5)
        var clip = MediaClip.image(portrait, duration: duration).transform(VisualTransform(contentMode: .stretch))
        if video {
            let source = folder.appendingPathComponent("source.mp4")
            try await VideoExporter().export(VideoProject(canvas: VideoSize(width: 320, height: 180)) {
                MediaTrack(clips: [clip])
            }, to: source)
            clip = MediaClip.video(source, duration: duration).audio(AudioSettings(isMuted: true))
        }
        // Emulator GL drivers reject the SSBO query used by MediaPipe's GPU delegate.
        // Only inference uses CPU here; the production GL composition path is unchanged.
        let registry = try EffectRegistry(visual: [PersonSegmentation.definition(appleModelURL: useVision ? nil : model, androidModelURL: model, androidCompute: .cpu)])
        let output = folder.appendingPathComponent("person.mp4")
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), background: VideoColor(red: 1, green: 0, blue: 0)) {
            MediaTrack(clips: [clip]).filter(PersonSegmentation.filter())
        }
        try await VideoExporter(effects: registry).export(project, to: output)
        let pixels = try await framePixels(output, points: [16, 18, 160, 140, 304, 162])
        for offset in [0, 6] {
            #expect(pixels[offset] > 190 && pixels[offset + 1] < 65 && pixels[offset + 2] < 65,
                    "The original blue background must reveal the red canvas: \(pixels)")
        }
        #expect(pixels[3] > 130 && pixels[4] > 80 && pixels[5] < 90,
                "The person's yellow shirt must remain: \(pixels)")
    }

    @Test(arguments: [false, true]) func invalidSegmentationModelFailsCleanlyAndValidModelRecovers(missing: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("person-model-failure-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let portrait = try segmentationFixture("person", extension: "png", folder: folder)
        let invalid = folder.appendingPathComponent("invalid-model")
        if !missing { try Data("invalid model".utf8).write(to: invalid) }
        let duration = try VideoTime(value: 1, timescale: 5)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180)) {
            MediaTrack(clips: [MediaClip.image(portrait, duration: duration)])
                .filter(PersonSegmentation.filter())
        }
        let output = folder.appendingPathComponent("person.mp4")
        let invalidEffects = try EffectRegistry(visual: [PersonSegmentation.definition(appleModelURL: invalid, androidModelURL: invalid, androidCompute: .cpu)])
        await #expect(throws: VideoError.self) { try await VideoExporter(effects: invalidEffects).export(project, to: output) }
        #expect(!FileManager.default.fileExists(atPath: output.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".swiftvideo-") })
        let valid = try segmentationModel(folder: folder)
        let validEffects = try EffectRegistry(visual: [PersonSegmentation.definition(appleModelURL: valid, androidModelURL: valid, androidCompute: .cpu)])
        try await VideoExporter(effects: validEffects).export(project, to: output)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }

    private func segmentationFixture(_ name: String, extension suffix: String, folder: URL) throws -> URL {
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "\(name).\(suffix)"))
        let destination = folder.appendingPathComponent("\(name).\(suffix)")
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
        #else
        return try #require(Bundle.module.url(forResource: name, withExtension: suffix))
        #endif
    }

    private func segmentationModel(folder: URL) throws -> URL {
        #if os(Android)
        return try segmentationFixture("selfie_segmenter", extension: "tflite", folder: folder)
        #else
        return try #require(Bundle.module.url(forResource: "DeepLabV3FP16", withExtension: "mlmodelc")
                            ?? Bundle.module.url(forResource: "DeepLabV3FP16", withExtension: "mlmodel"))
        #endif
    }

}
#endif
