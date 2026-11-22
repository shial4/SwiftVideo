// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
@testable import SwiftVideo
#if os(Android)
import SwiftVideoTestSupport
#else
import AVFoundation
import CoreGraphics
#endif

@Suite(.serialized) struct RenderBehaviorTests {
    @Test func repeatingBezierOpacityReachesBothRenderers() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("timing-curve-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer { try? FileManager.default.removeItem(at: image) }
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let clip = try MediaClip.image(image, duration: VideoTime(value: 6, timescale: 5)).animate(.opacity, keyframes: [
            Keyframe(time: .zero, value: 0, curve: CubicBezierTiming(x1: 0, y1: 1, x2: 0, y2: 1)),
            Keyframe(time: VideoTime(value: 4, timescale: 5), value: 1)
        ], repetition: .forever())
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), background: VideoColor(red: 0, green: 0, blue: 1),
            tracks: [MediaTrack(clips: [clip])])
        let destination = folder.appendingPathComponent("repeat.mp4")
        try await VideoExporter().export(project, to: destination)
        let early = try await centerPixel(destination, at: 0.1), boundary = try await centerPixel(destination, at: 0.8)
        let repeated = try await centerPixel(destination, at: 0.9)
        for pixel in [early, repeated] {
            // Encoded RGB depends on each backend's compositing color space. The
            // Bezier sample is green-dominant; linear 12.5% opacity is blue-dominant.
            #expect(pixel[1] > 180 && pixel[1] - pixel[2] > 100, "Bezier output should be green-dominant: \(pixel)")
        }
        #expect(boundary[2] > 190 && boundary[1] < 30, "Repeat boundary should reveal the background: \(boundary)")
    }

    @Test(arguments: [false, true]) func customEffectClockSurvivesRetimingTrimmingAndSplitting(video: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-clock-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: video ? "blue.mp4" : "green.png"))
        #else
        let source = try #require(Bundle.module.url(forResource: video ? "blue" : "green", withExtension: video ? "mp4" : "png"))
        #endif
        let fifth = try VideoTime(value: 1, timescale: 5)
        let clip = try MediaClip(source: video ? .video(source) : .image(source), start: fifth,
            duration: VideoTime(value: 4, timescale: 5), sourceStart: VideoTime(value: 1, timescale: 10),
            audio: AudioSettings(isMuted: true)).speed(.double)
        let track = try MediaTrack(clips: [clip]).speed(.quarter).filter(.custom(EffectReference(CustomEffectFixture.clockID)))
        let editor = try VideoEditor(project: VideoProject(tracks: [track]))
        _ = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: VideoTime(value: 2, timescale: 5), duration: VideoTime(value: 4, timescale: 5)))])
        let project = try await editor.apply([.split(clip.id, at: VideoTime(value: 1, timescale: 1), rightID: UUID())])
        let destination = folder.appendingPathComponent("clock.mp4")
        try await VideoExporter(effects: CustomEffectFixture.clockRegistry()).export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let early = try await centerPixel(destination, at: 0.8)
        let later = try await centerPixel(destination, at: 1.2)
        #expect(early[1] > 190 && early[0] < 35 && early[2] < 35, "Before split: \(early)")
        #expect(later[2] > 190 && later[0] < 35 && later[1] < 35, "After split: \(later)")
    }

    @Test(arguments: [false, true]) func customGPUFiltersChangeImageAndVideoPixels(video: Bool) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-effect-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: video ? "blue.mp4" : "green.png"))
        #else
        let source = try #require(Bundle.module.url(forResource: video ? "blue" : "green", withExtension: video ? "mp4" : "png"))
        #endif
        let clip = MediaClip(source: video ? .video(source) : .image(source), duration: try VideoTime(value: 1, timescale: 1),
                             audio: AudioSettings(isMuted: true))
        let project = VideoProject(tracks: [MediaTrack(clips: [clip]).filter(.custom(EffectReference(CustomEffectFixture.id)))])
        let destination = folder.appendingPathComponent("custom.mp4")
        try await VideoExporter(effects: CustomEffectFixture.registry()).export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let rgb = try await centerPixel(destination)
        // Channel rotation maps green images to red and blue video to green.
        let selected = video ? 1 : 0
        #expect(rgb[selected] > 190, "Decoded RGB: \(rgb)")
        // Compare channel separation: codec/color conversion can retain small residuals.
        #expect(rgb.enumerated().filter { $0.offset != selected }.allSatisfy { rgb[selected] - $0.element > 150 }, "Decoded RGB: \(rgb)")
    }

    @Test func customClipFilterRunsBeforeBuiltInTrackFilters() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-order-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let clip = MediaClip.image(image, duration: try VideoTime(value: 1, timescale: 1))
            .filter(.custom(EffectReference(CustomEffectFixture.id)))
        let project = VideoProject(tracks: [MediaTrack(clips: [clip]).filter(.saturation(0))])
        let destination = folder.appendingPathComponent("ordered.mp4")
        try await VideoExporter(effects: CustomEffectFixture.registry()).export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let rgb = try await centerPixel(destination)
        #expect(abs(rgb[0] - rgb[1]) < 12 && abs(rgb[1] - rgb[2]) < 12, "Decoded RGB: \(rgb)")
        // Desaturating red after rotation is darker than desaturating the original green.
        #expect(rgb.allSatisfy { $0 > 25 && $0 < 170 }, "Decoded RGB: \(rgb)")
    }

    @Test func customGPUAlphaCompositesWithoutPremultiplyingTwice() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-alpha-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let clip = MediaClip.image(image, duration: try VideoTime(value: 1, timescale: 1))
            .filter(.custom(EffectReference(CustomEffectFixture.id, parameters: ["opacity": .number(0.5)])))
        let project = VideoProject(background: VideoColor(red: 0, green: 0, blue: 1), tracks: [MediaTrack(clips: [clip])])
        let destination = folder.appendingPathComponent("alpha.mp4")
        try await VideoExporter(effects: CustomEffectFixture.registry()).export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let rgb = try await centerPixel(destination)
        #expect(rgb[1] < 30, "Decoded RGB: \(rgb)")
        #expect(rgb[0] > 80 && rgb[0] < 220 && rgb[2] > 80 && rgb[2] < 220, "Decoded RGB: \(rgb)")
        #expect(abs(rgb[0] - rgb[2]) < 25, "Half-transparent red should contribute as much as its blue background: \(rgb)")
    }

    @Test func unregisteredCustomEffectFailsBeforeMediaIO() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-missing-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.image(folder.appendingPathComponent("missing.png"), duration: try VideoTime(value: 1, timescale: 1))
            .filter(.custom(EffectReference(CustomEffectFixture.id)))
        await #expect(throws: VideoError.unsupportedFeature("Effect 'test.channel-rotation' version 1 is not registered.")) {
            try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: folder.appendingPathComponent("output.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func failingGPUImplementationCleansUpAndExporterCanBeReused() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-failure-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let clip = MediaClip.image(image, duration: try VideoTime(value: 1, timescale: 1))
        let exporter = VideoExporter(effects: try CustomEffectFixture.failingRegistry())
        let settings = ExportSettings(resolution: VideoSize(width: 320, height: 180))
        let destination = folder.appendingPathComponent("output.mp4")
        await #expect(throws: VideoError.self) {
            try await exporter.export(VideoProject(tracks: [MediaTrack(clips: [clip.filter(.custom(EffectReference(CustomEffectFixture.failingID)))])]),
                                      to: destination, settings: settings)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        try await exporter.export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: destination, settings: settings)
        let rgb = try await centerPixel(destination)
        #expect(rgb[1] > 190 && rgb[0] < 35 && rgb[2] < 35, "Decoded RGB after recovery: \(rgb)")
    }

    @Test(arguments: ["red.mp4", "blue.mp4", "bt709.mp4"])
    func unfilteredVideoPreservesDecodedColor(fixture: String) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("color-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: fixture))
        defer { try? FileManager.default.removeItem(at: source) }
        #else
        let name = (fixture as NSString).deletingPathExtension
        let source = try #require(Bundle.module.url(forResource: name, withExtension: "mp4"))
        #endif
        let destination = folder.appendingPathComponent("export.mp4")
        for start in fixture == "bt709.mp4" ? [0, 3] : [0] {
            let before = try await frameSample(source, seconds: Double(start) + 0.5, leftQuarter: true)
            let size = before.size
            let project = VideoProject(canvas: size, tracks: [MediaTrack(clips: [
                MediaClip(source: .video(source), duration: try VideoTime(value: 1, timescale: 1),
                          sourceStart: try VideoTime(value: Int64(start), timescale: 1))
            ])])
            try await VideoExporter().export(project, to: destination,
                settings: ExportSettings(resolution: size, videoBitRate: 4_000_000))
            let after = try await frameSample(destination, leftQuarter: true)
            #expect(after.size == before.size)
            // Compare decoded pixels through the same device decoder. Flat fixture
            // interiors should tolerate codec rounding, not a changed color matrix.
            for channel in 0..<3 {
                #expect(abs(after.rgb[channel] - before.rgb[channel]) <= 8,
                        "\(fixture) at \(start)s channel \(channel): source \(before.rgb[channel]), export \(after.rgb[channel])")
            }
            try FileManager.default.removeItem(at: destination)
        }
    }

    @Test func filtersAffectDecodedPixels() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("filter-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        #endif
        let duration = try VideoTime(value: 1, timescale: 1)
        let clip = MediaClip(source: .image(image), duration: duration,
                             transform: VisualTransform(crop: VideoCrop(x: 0.25, y: 0.25, width: 0.5, height: 0.5), contentMode: .fill),
                             filters: [.saturation(0), .brightness(0.1)])
        let destination = folder.appendingPathComponent("filtered.mp4")
        try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip]).filter(.contrast(1.1)).filter(.gaussianBlur(2))]), to: destination,
                                         settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let rgb = try await centerPixel(destination)
        #expect(abs(rgb[0] - rgb[1]) < 12 && abs(rgb[1] - rgb[2]) < 12)
        #expect(rgb.allSatisfy { $0 > 90 && $0 < 250 })
    }

    @Test func overlappingLayersRespectOpacityAndZOrder() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("overlap-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let video = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "blue.mp4"))
        #else
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        let video = try #require(Bundle.module.url(forResource: "blue", withExtension: "mp4"))
        #endif
        let duration = try VideoTime(value: 1, timescale: 1)
        let top = MediaClip(source: .image(image), duration: duration, zIndex: 5,
                            transform: VisualTransform(scale: 0.8, rotation: 20, opacity: 0.5, contentMode: .fill))
        let bottom = MediaClip(source: .video(video), duration: duration, audio: AudioSettings(isMuted: true))
        // Reverse storage order deliberately: zIndex determines compositing order.
        let project = VideoProject(tracks: [MediaTrack(clips: [top, bottom])])
        let destination = folder.appendingPathComponent("overlap.mp4")
        try await VideoExporter().export(project, to: destination,
                                         settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        let rgb = try await centerPixel(destination)
        #expect(rgb[0] < 30, "Decoded RGB: \(rgb)")
        // Apple blends in linear light; Media3 may blend encoded SDR values.
        // Both contributions must remain visible without either becoming opaque.
        #expect(rgb[1] > 80 && rgb[1] < 220, "Decoded RGB: \(rgb)")
        #expect(rgb[2] > 80 && rgb[2] < 220, "Decoded RGB: \(rgb)")
        #expect(abs(rgb[1] - rgb[2]) < 25, "Decoded RGB: \(rgb)")
    }

    @Test func missingMediaRemovesStagingOnEitherPlatform() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("missing-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip(source: .video(folder.appendingPathComponent("missing.mp4")),
                             duration: try VideoTime(value: 1, timescale: 1))
        await #expect(throws: VideoError.self) {
            try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: folder.appendingPathComponent("output.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    private func centerPixel(_ url: URL, at seconds: Double = 0.5) async throws -> [Double] {
        try await frameSample(url, seconds: seconds).rgb
    }

    private func frameSample(_ url: URL, seconds: Double = 0.5, leftQuarter: Bool = false) async throws
        -> (size: VideoSize, rgb: [Double]) {
        #if os(Android)
        let stats = try Media3TestSupport.frameStats(path: url.path, timeUs: Int64(seconds * 1_000_000))
        let size = VideoSize(width: Int(stats[0]), height: Int(stats[1]))
        return (size, Array(leftQuarter ? stats[10...12] : stats[3...5]))
        #else
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let index = (image.height / 2 * image.width + image.width / (leftQuarter ? 4 : 2)) * 4
        return (VideoSize(width: image.width, height: image.height), bytes[index..<(index + 3)].map(Double.init))
        #endif
    }
}
#endif
