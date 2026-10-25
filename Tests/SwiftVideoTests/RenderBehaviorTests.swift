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
                             filters: [.saturation(0), .brightness(0.1), .contrast(1.1), .gaussianBlur(2)])
        let destination = folder.appendingPathComponent("filtered.mp4")
        try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: destination,
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

    private func centerPixel(_ url: URL) async throws -> [Double] {
        #if os(Android)
        let stats = try Media3TestSupport.frameStats(path: url.path, timeUs: 500_000)
        return Array(stats[3...5])
        #else
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        let image = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { storage in
            let context = try #require(CGContext(data: storage.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        let index = (image.height / 2 * image.width + image.width / 2) * 4
        return bytes[index..<(index + 3)].map(Double.init)
        #endif
    }
}
#endif
