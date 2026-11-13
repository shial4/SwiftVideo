// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Synchronization
import Testing
import SwiftVideoTestSupport
@testable import SwiftVideo

extension RenderBehaviorTests {
    @Test(arguments: [false, true]) func nativeVisualEffectCompositesImagesAndVideo(video: Bool) async throws {
        let calls = Mutex(0)
        let id = EffectIdentifier("test.native-opacity")
        let implementation = AndroidVisualEffect(nativeFactory: {
            calls.withLock { $0 += 1 }
            return try Media3TestSupport.nativeOpacityEffect(0.5)
        })
        let registry = try EffectRegistry(visual: [VisualEffectDefinition(id).android { _ in implementation }])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-effect-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: video ? "blue.mp4" : "green.png"))
        defer { try? FileManager.default.removeItem(at: source) }
        let clip = MediaClip(source: video ? .video(source) : .image(source), duration: try VideoTime(value: 1, timescale: 5),
            transform: VisualTransform(contentMode: .stretch), audio: AudioSettings(isMuted: true))
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), background: VideoColor(red: 1, green: 0, blue: 0)) {
            MediaTrack(clips: [clip]).filter(.custom(EffectReference(id)))
        }
        // Native handles are out of band. Project/plan JSON contain only references and data.
        let restored = try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project))
        let plan = try JSONEncoder().encode(AndroidRenderPlan(project: restored, settings: ExportSettings(), effects: registry))
        let json = try #require(String(data: plan, encoding: .utf8))
        #expect(json.contains("\"kind\":\"native\""))
        #expect(!json.contains("nativeFactory"))
        #expect(throws: EncodingError.self) { try JSONEncoder().encode(implementation) }
        #expect(calls.withLock { $0 } == 0)
        let output = folder.appendingPathComponent("output.mp4")
        try await VideoExporter(effects: registry).export(restored, to: output)
        #expect(calls.withLock { $0 } == 1)
        let pixels = try Media3TestSupport.framePixels(path: output.path, timeUs: 100_000, points: [160, 90])
        #expect(pixels[0] > 80 && pixels[0] < 220)
        #expect(pixels[video ? 2 : 1] > 80 && pixels[video ? 2 : 1] < 220)
        #expect(pixels[video ? 1 : 2] < 30)
    }

    @Test func nativeVisualFactoryFailureCleansUpAndAllowsAnotherExport() async throws {
        let id = EffectIdentifier("test.native-failure")
        let registry = try EffectRegistry(visual: [VisualEffectDefinition(id).android { _ in
            AndroidVisualEffect(nativeFactory: { throw VideoError.renderingFailed("Native factory failed") })
        }])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("native-failure-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.text("Native", duration: try VideoTime(value: 1, timescale: 5))
        let exporter = VideoExporter(effects: registry)
        let output = folder.appendingPathComponent("output.mp4")
        let failed = VideoProject(canvas: VideoSize(width: 320, height: 180)) {
            MediaTrack(clips: [clip.filter(.custom(EffectReference(id)))])
        }
        await #expect(throws: VideoError.self) { try await exporter.export(failed, to: output) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        try await exporter.export(VideoProject(canvas: VideoSize(width: 320, height: 180)) { MediaTrack(clips: [clip]) }, to: output)
        #expect(FileManager.default.fileExists(atPath: output.path))
    }
}
#endif
