// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
import SwiftVideoTestSupport
@testable import SwiftVideo

@Suite struct AndroidLayerPreviewTests {
    @Test func croppedVideoLayerUsesTrimmedSourceClock() async throws {
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "bt709.mp4"))
        let folder = source.deletingLastPathComponent()
        let first = folder.appendingPathComponent("layer-early-\(UUID()).png")
        let second = folder.appendingPathComponent("layer-late-\(UUID()).png")
        defer {
            for url in [source, first, second] { try? FileManager.default.removeItem(at: url) }
        }
        let clip = MediaClip(source: .video(source), start: try VideoTime(value: 2, timescale: 1),
            duration: try VideoTime(value: 2, timescale: 1), sourceStart: try VideoTime(value: 1, timescale: 1),
            transform: VisualTransform(crop: VideoCrop(width: 0.5), contentMode: .fill))
        let project = VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [MediaTrack(clips: [clip])])
        let renderer = VideoLayerRenderer()
        try await renderer.render(clipID: clip.id, in: project, at: VideoTime(value: 22, timescale: 10), to: first)
        try await renderer.render(clipID: clip.id, in: project, at: VideoTime(value: 38, timescale: 10), to: second)
        let red = try Media3TestSupport.layerImageStats(path: first.path)
        let green = try Media3TestSupport.layerImageStats(path: second.path)
        try #require(red.count == 10 && green.count == 10)
        #expect(red[0] == 160 && red[1] == 90 && green[0] == 160 && green[1] == 90)
        #expect(red[6] > 200 && red[7] < 60 && red[8] < 60)
        #expect(green[7] > 200 && green[6] < 60 && green[8] < 60)
        #expect(red[9] == 255 && green[9] == 255)
    }

    @Test func transparentTextAndFilteredImageRenderWithoutAnEncoder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("layer-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let duration = try VideoTime(value: 2, timescale: 1)
        let clip = MediaClip.text("Preview", duration: duration, style: TextStyle(fontSize: 48))
            .transform(VisualTransform(x: 0.8, width: 0.8, height: 0.4, scale: 2, rotation: 30, opacity: 0.2))
        let canvas = VideoSize(width: 640, height: 360)
        let renderer = VideoLayerRenderer()
        let text = folder.appendingPathComponent("text.png")
        let started = ContinuousClock.now
        try await renderer.render(clipID: clip.id, in: VideoProject(canvas: canvas, tracks: [MediaTrack(clips: [clip])]),
            at: .zero, canvasSize: VideoSize(width: 320, height: 180), to: text)
        print("Android layer image duration: \(started.duration(to: .now))")
        let stats = try Media3TestSupport.layerImageStats(path: text.path)
        try #require(stats.count == 10)
        #expect(stats[0] == 256 && stats[1] == 72)
        #expect(stats[2] > 0 && stats[3] > 0)
        #expect(stats[4] > 0 && stats[5] == 0, "Text must remain upright at the top of its local layer")

        let image = URL(fileURLWithPath: try Media3TestSupport.solidImage(red: 255, green: 0, blue: 0))
        defer { try? FileManager.default.removeItem(at: image) }
        let photo = MediaClip.image(image, duration: duration).filter(.saturation(0))
        let noir = folder.appendingPathComponent("noir.png")
        try await renderer.render(clipID: photo.id, in: VideoProject(canvas: VideoSize(width: 160, height: 90),
            tracks: [MediaTrack(clips: [photo])]), at: .zero, to: noir)
        let gray = try Media3TestSupport.layerImageStats(path: noir.path)
        try #require(gray.count == 10)
        #expect(gray[0] == 160 && gray[1] == 90)
        #expect(abs(gray[6] - gray[7]) <= 2 && abs(gray[7] - gray[8]) <= 2)
        #expect(gray[9] == 255)
    }
}
#endif
