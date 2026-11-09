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

extension RenderBehaviorTests {
    @Test(arguments: [false, true]) func masksUseSourceCoordinatesBeforeCropOnImagesAndVideo(video: Bool) async throws {
        try await withMaskedExport(video: video, filters: [.mask(VideoMask(shape: .rectangle,
            bounds: VideoCrop(x: 0.25, y: 0.1, width: 0.5, height: 0.5)))],
            transform: VisualTransform(crop: VideoCrop(x: 0.25, width: 0.5), contentMode: .stretch)) { url in
            let pixels = try await maskPixels(url, points: [32, 45, 160, 45, 288, 45, 160, 144])
            for offset in [0, 3, 6] { #expect(pixels[offset + (video ? 2 : 1)] > 200, "Full source mask width survives crop: \(pixels)") }
            #expect(pixels[9] > 200 && pixels[10] < 30 && pixels[11] < 30, "Top-left mask coordinates: \(pixels)")
        }
    }

    @Test(arguments: [false, true]) func ellipseMaskAndItsInverseKeepOppositePixels(inverted: Bool) async throws {
        try await withMaskedExport(filters: [.mask(VideoMask(bounds: VideoCrop(x: 0.1, y: 0.1, width: 0.8, height: 0.8), inverted: inverted))]) { url in
            let pixels = try await maskPixels(url, points: [160, 90, 40, 25, 8, 90])
            #expect(pixels[inverted ? 0 : 1] > 200, "Ellipse center: \(pixels)")
            #expect(pixels[inverted ? 4 : 3] > 200, "Ellipse corner: \(pixels)")
            #expect(pixels[inverted ? 7 : 6] > 200, "Outside bounds: \(pixels)")
        }
    }

    @Test func featheredTrackMaskRetainsBothForegroundAndBackground() async throws {
        // Sample the outer boundary, inward fade and opaque center separately.
        let mask = VideoMask(shape: .rectangle, bounds: VideoCrop(x: 0.2, y: 0.1, width: 0.6, height: 0.8), feather: 0.4)
        try await withMaskedExport(trackFilters: [.mask(mask)]) { url in
            let pixels = try await maskPixels(url, points: [64, 90, 92, 90, 160, 90])
            #expect(pixels[0] > 200 && pixels[1] < 45)
            #expect(pixels[3] > 80 && pixels[3] < 220 && pixels[4] > 80 && pixels[4] < 220, "Feather blend: \(pixels)")
            #expect(pixels[7] > 200 && pixels[6] < 30)
        }
    }

    @Test(arguments: [false, true]) func chromaKeyRemovesTheKeyColorFromImagesAndVideo(video: Bool) async throws {
        let color = video ? VideoColor(red: 0, green: 0, blue: 1) : VideoColor(red: 0, green: 1, blue: 0)
        try await withMaskedExport(video: video, filters: [.chromaKey(ChromaKey(color: color))]) { url in
            let pixels = try await maskPixels(url, points: [160, 90])
            #expect(pixels[0] > 220 && pixels[1] < 30 && pixels[2] < 30, "Keying should reveal the red background: \(pixels)")
        }
    }

    @Test func chromaKeySoftnessBlendsInsteadOfCuttingAtTheThreshold() async throws {
        let color = VideoColor(red: 0, green: 0.5, blue: 0)
        // Linear sRGB 0.5 is 0.214041. Distance from full green is 0.453774.
        let key = ChromaKey(color: color, tolerance: 0.353774, softness: 0.2)
        try await withMaskedExport(filters: [.chromaKey(key)]) { url in
            let pixels = try await maskPixels(url, points: [160, 90])
            #expect(pixels[0] > 80 && pixels[0] < 220 && pixels[1] > 80 && pixels[1] < 220, "Soft key: \(pixels)")
            #expect(abs(pixels[0] - pixels[1]) < 35 && pixels[2] < 30, "Half coverage must retain both colors: \(pixels)")
        }
    }

    @Test func chromaKeyPreservesExistingAlphaAndRunsAfterTheClipFilter() async throws {
        let custom = MediaFilter.custom(EffectReference(CustomEffectFixture.id, parameters: ["opacity": .number(0.5)]))
        try await withMaskedExport(filters: [custom], trackFilters: [.chromaKey(ChromaKey())],
            background: VideoColor(red: 0, green: 0, blue: 1), effects: CustomEffectFixture.registry()) { url in
            let pixels = try await maskPixels(url, points: [160, 90])
            #expect(pixels[0] > 80 && pixels[0] < 220 && pixels[2] > 80 && pixels[2] < 220, "Retained input alpha: \(pixels)")
            #expect(abs(pixels[0] - pixels[2]) < 30 && pixels[1] < 30)
        }
    }

    private func withMaskedExport(video: Bool = false, filters: [MediaFilter] = [], trackFilters: [MediaFilter] = [],
                                  transform: VisualTransform = VisualTransform(contentMode: .stretch),
                                  background: VideoColor = VideoColor(red: 1, green: 0, blue: 0), effects: EffectRegistry = .empty,
                                  inspect: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("mask-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: video ? "blue.mp4" : "green.png"))
        defer { try? FileManager.default.removeItem(at: source) }
        #else
        let source = try #require(Bundle.module.url(forResource: video ? "blue" : "green", withExtension: video ? "mp4" : "png"))
        #endif
        let clip = MediaClip(source: video ? .video(source) : .image(source), duration: try VideoTime(value: 1, timescale: 5),
            transform: transform, filters: filters, audio: AudioSettings(isMuted: true))
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), background: background,
            tracks: [MediaTrack(clips: [clip], filters: trackFilters)])
        let output = folder.appendingPathComponent("mask.mp4")
        try await VideoExporter(effects: effects).export(project, to: output)
        try await inspect(output)
    }

    private func maskPixels(_ url: URL, points: [Int]) async throws -> [Double] {
        #if os(Android)
        return try Media3TestSupport.framePixels(path: url.path, timeUs: 100_000, points: points)
        #else
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(value: 1, timescale: 10)).image
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return stride(from: 0, to: points.count, by: 2).flatMap { index in
            let offset = (points[index + 1] * image.width + points[index]) * 4
            return bytes[offset..<(offset + 3)].map(Double.init)
        }
        #endif
    }
}
#endif
