// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation) || (os(Android) && !SWIFTVIDEO_CORE_COVERAGE)
import Foundation
import Testing
@testable import SwiftVideo
#if os(Android)
import SwiftVideoTestSupport
#else
import CoreGraphics
import ImageIO
#endif

@Suite struct LayerPlaybackTests {
    @Test(arguments: [(PlaybackRate.normal, PlaybackRate.normal), (.double, .normal), (.normal, .double)])
    func layerPreviewInheritsClipAndTrackSpeed(rates: (PlaybackRate, PlaybackRate)) async throws {
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "bt709.mp4"))
        defer { try? FileManager.default.removeItem(at: source) }
        #else
        let source = try #require(Bundle.module.url(forResource: "bt709", withExtension: "mp4"))
        #endif
        let clip = MediaClip(source: .video(source), start: try VideoTime(value: 2, timescale: 1),
            duration: try VideoTime(value: 2, timescale: 1), sourceStart: try VideoTime(value: 1, timescale: 1),
            transform: VisualTransform(crop: VideoCrop(width: 0.5), contentMode: .fill), playbackRate: rates.0)
        let track = MediaTrack(clips: [clip], playbackRate: rates.1)
        let time = try VideoTime(value: 3, timescale: 1)
        let size = VideoSize(width: 160, height: 90)
        let renderer = VideoLayerRenderer()
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("layer-speed-\(UUID()).png")
        let filtered = FileManager.default.temporaryDirectory.appendingPathComponent("layer-track-filter-\(UUID()).png")
        defer { for url in [file, filtered] { try? FileManager.default.removeItem(at: url) } }
        try await renderer.render(clipID: clip.id, in: VideoProject(canvas: size, tracks: [track]), at: time, to: file)
        let color = try center(file)
        let channel = rates.0 == .normal && rates.1 == .normal ? 0 : 1
        #expect(color[channel] > 200 && color[1 - channel] < 60 && color[2] < 60)
        try await renderer.render(clipID: clip.id, in: VideoProject(canvas: size, tracks: [track.filter(.saturation(0))]), at: time, to: filtered)
        let gray = try center(filtered)
        #expect(abs(gray[0] - gray[1]) <= 2 && abs(gray[1] - gray[2]) <= 2)
    }

    @Test func layerMaskUsesSourceCoordinatesBeforeCrop() async throws {
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer { try? FileManager.default.removeItem(at: source) }
        #else
        let source = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let clip = MediaClip.image(source, duration: try VideoTime(value: 1, timescale: 1))
            .filter(.mask(VideoMask(shape: .rectangle, bounds: VideoCrop(width: 0.5))))
            .transform(VisualTransform(crop: VideoCrop(x: 0.5, width: 0.5), contentMode: .stretch))
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("layer-mask-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: output) }
        try await VideoLayerRenderer().render(clipID: clip.id,
            in: VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [MediaTrack(clips: [clip])]),
            at: .zero, to: output)
        #expect(try center(output)[3] == 0, "Cropping the masked-out source half must remain transparent.")
    }

    @Test func unregisteredPreviewEffectsFailBeforeWriting() async throws {
        let title = MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1))
        let clips = [title.filter(.custom(EffectReference(EffectIdentifier("app.preview"))))]
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("unsupported-preview-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: output) }
        for clip in clips {
            let project = VideoProject(tracks: [MediaTrack(clips: [clip])])
            await #expect(throws: VideoError.self) {
                try await VideoLayerRenderer().render(clipID: clip.id, in: project, at: .zero, to: output)
            }
            #expect(!FileManager.default.fileExists(atPath: output.path))
            #if os(Android)
            #expect(throws: VideoError.self) { try AndroidVideoPreview(project: project, settings: ExportSettings()) }
            #endif
        }
    }

    @Test(arguments: [false, true])
    func registeredLayerEffectsRetainEditedTimelineClocks(video: Bool) async throws {
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: video ? "blue.mp4" : "green.png"))
        defer { try? FileManager.default.removeItem(at: source) }
        #else
        let source = try #require(Bundle.module.url(forResource: video ? "blue" : "green", withExtension: video ? "mp4" : "png"))
        #endif
        let clip = MediaClip(source: video ? .video(source) : .image(source), start: try VideoTime(value: 1, timescale: 5),
            duration: try VideoTime(value: 8, timescale: 5), sourceStart: try VideoTime(value: 1, timescale: 10),
            playbackRate: .half)
        let project = VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [
            MediaTrack(clips: [clip]).filter(.custom(EffectReference(CustomEffectFixture.clockID)))
        ])
        let editor = try VideoEditor(project: project)
        _ = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: VideoTime(value: 2, timescale: 5), duration: VideoTime(value: 4, timescale: 5)))])
        let rightID = UUID()
        let edited = try await editor.apply([.split(clip.id, at: VideoTime(value: 1, timescale: 1), rightID: rightID)])
        let renderer = try VideoLayerRenderer(effects: CustomEffectFixture.clockRegistry())
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("layer-clock-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        for (id, tenths, channel) in [(clip.id, Int64(8), 1), (rightID, Int64(12), 2)] {
            let output = folder.appendingPathComponent("\(tenths).png")
            try await renderer.render(clipID: id, in: edited, at: VideoTime(value: tenths, timescale: 10), to: output)
            let rgba = try center(output)
            #expect(rgba[channel] > 240 && rgba[0] < 10 && rgba[3] == 255, "Effect clock: \(rgba)")
        }
    }

    @Test func motionLayerUsesRequestedTimeAndRecoversAfterEffectFailure() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("motion-layer-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = try MediaClip.text("TITLE", duration: VideoTime(value: 2, timescale: 1), style: TextStyle(fontSize: 36))
            .textMotion(.fadeUp(duration: VideoTime(value: 1, timescale: 2)))
            .starting(at: VideoTime(value: 1, timescale: 1))
        let renderer = try VideoLayerRenderer(effects: CustomEffectFixture.failingRegistry())
        let invalid = clip.filter(.custom(EffectReference(CustomEffectFixture.failingID)))
        let failed = folder.appendingPathComponent("failed.png")
        await #expect(throws: VideoError.self) {
            try await renderer.render(clipID: invalid.id,
                in: VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [MediaTrack(clips: [invalid])]),
                at: VideoTime(value: 2, timescale: 1), to: failed)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        let project = VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [MediaTrack(clips: [clip])])
        for second in [Int64(1), 2] {
            let output = folder.appendingPathComponent("\(second).png")
            try await renderer.render(clipID: clip.id, in: project, at: VideoTime(value: second, timescale: 1), to: output)
            #if os(Android)
            let visible = try Media3TestSupport.layerImageStats(path: output.path)[3]
            #else
            let image = try #require(CGImageSourceCreateWithURL(output as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            let context = try #require(CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 90))
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            let visible = stride(from: 3, to: 160 * 90 * 4, by: 4).filter { bytes[$0] == 255 }.count
            #endif
            #expect(second == 1 ? visible == 0 : visible > 100, "Motion at \(second): \(visible) opaque pixels")
        }
    }

    private func center(_ url: URL) throws -> [Int] {
        #if os(Android)
        let stats = try Media3TestSupport.layerImageStats(path: url.path)
        try #require(stats.count == 10)
        return Array(stats[6...9])
        #else
        let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let context = try #require(CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 90))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<4).map { Int(bytes[(45 * 160 + 80) * 4 + $0]) }
        #endif
    }
}
#endif
