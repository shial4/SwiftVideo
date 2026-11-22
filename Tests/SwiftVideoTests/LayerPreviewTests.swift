// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import Foundation
import CoreGraphics
import ImageIO
import Testing
@testable import SwiftVideo

@Suite struct LayerPreviewTests {
    @Test func croppedVideoLayerUsesTrimmedSourceClock() async throws {
        let source = try #require(Bundle.module.url(forResource: "bt709", withExtension: "mp4"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("layer-clock-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip(source: .video(source), start: try VideoTime(value: 2, timescale: 1),
            duration: try VideoTime(value: 2, timescale: 1), sourceStart: try VideoTime(value: 1, timescale: 1),
            transform: VisualTransform(crop: VideoCrop(width: 0.5), contentMode: .fill))
        let project = VideoProject(canvas: VideoSize(width: 160, height: 90), tracks: [MediaTrack(clips: [clip])])
        let renderer = VideoLayerRenderer()
        for (index, time) in [22, 38].enumerated() {
            let url = folder.appendingPathComponent("frame-\(index).png")
            try await renderer.render(clipID: clip.id, in: project, at: VideoTime(value: Int64(time), timescale: 10), to: url)
            let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            #expect(image.width == 160 && image.height == 90)
            let context = try #require(CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640,
                space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 90))
            let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            let pixel = (45 * 160 + 80) * 4
            #expect(bytes[pixel + index] > 200 && bytes[pixel + 1 - index] < 60 && bytes[pixel + 2] < 60)
            #expect(bytes[pixel + 3] == 255)
        }
    }

    @Test func imageCropFitAndFiltersUseTheNativeRasterPath() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("layer-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.png")
        let sRGB = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let drawing = try #require(CGContext(data: nil, width: 32, height: 16, bitsPerComponent: 8, bytesPerRow: 128,
            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        drawing.setFillColor(try #require(CGColor(colorSpace: sRGB, components: [1, 0, 0, 1])))
        drawing.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        drawing.setFillColor(try #require(CGColor(colorSpace: sRGB, components: [0, 1, 0, 1])))
        drawing.fill(CGRect(x: 16, y: 0, width: 16, height: 16))
        let destination = try #require(CGImageDestinationCreateWithURL(source as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(drawing.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        let duration = try VideoTime(value: 1, timescale: 1)
        let clip = MediaClip.image(source, duration: duration)
        let size = VideoSize(width: 64, height: 64)
        let renderer = VideoLayerRenderer()
        func render(_ clip: MediaClip, name: String) async throws -> [UInt8] {
            let url = folder.appendingPathComponent(name + ".png")
            try await renderer.render(clipID: clip.id, in: VideoProject(canvas: size, tracks: [MediaTrack(clips: [clip])]), at: .zero, to: url)
            let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
            let context = try #require(CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 256,
                space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: 64, height: 64))
            let pointer = try #require(context.data).assumingMemoryBound(to: UInt8.self)
            return Array(UnsafeBufferPointer(start: pointer, count: 64 * 64 * 4))
        }
        let fit = try await render(clip, name: "fit")
        #expect(fit[3] == 0)
        let left = (32 * 64 + 8) * 4, right = (32 * 64 + 56) * 4
        #expect(fit[left] > 240 && fit[left + 1] < 10)
        #expect(fit[right + 1] > 240 && fit[right] < 10)
        let cropped = clip.transform(VisualTransform(crop: VideoCrop(x: 0.5, width: 0.5)))
        let crop = try await render(cropped, name: "crop")
        #expect(crop[left + 1] > 240 && crop[left] < 10 && crop[3] == 255)
        let noir = try await render(cropped.filter(.saturation(0)), name: "noir")
        #expect(abs(Int(noir[left]) - Int(noir[left + 1])) <= 2)
        #expect(abs(Int(noir[left + 1]) - Int(noir[left + 2])) <= 2)
        #expect(noir[left + 3] == 255)
    }

    @Test func textRasterPreservesTransparencyAndExcludesPlacement() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("layer-test-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.text("Preview", duration: try VideoTime(value: 2, timescale: 1),
            style: TextStyle(fontSize: 48, color: VideoColor(red: 1, green: 0.2, blue: 0.1)))
            .transform(VisualTransform(x: 0.8, y: 0.2, width: 0.8, height: 0.4, scale: 2, rotation: 30, opacity: 0.2))
        let project = VideoProject(canvas: VideoSize(width: 640, height: 360), tracks: [MediaTrack(clips: [clip])])
        let renderer = VideoLayerRenderer()
        let original = folder.appendingPathComponent("original.png")
        let started = ContinuousClock.now
        try await renderer.render(clipID: clip.id, in: project, at: .zero, canvasSize: VideoSize(width: 320, height: 180), to: original)
        print("Layer preview duration: \(started.duration(to: .now))")
        let image = try #require(CGImageSourceCreateWithURL(original as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        #expect(image.width == 256 && image.height == 72)
        let context = try #require(CGContext(data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        let alpha = stride(from: 3, to: image.width * image.height * 4, by: 4).map { bytes[$0] }
        #expect(alpha.contains(0))
        #expect(alpha.contains(255))
        let unplaced = clip.transform(VisualTransform(width: 0.8, height: 0.4))
        let second = folder.appendingPathComponent("unplaced.png")
        try await renderer.render(clipID: clip.id, in: VideoProject(canvas: project.canvas, tracks: [MediaTrack(clips: [unplaced])]),
            at: .zero, canvasSize: VideoSize(width: 320, height: 180), to: second)
        #expect(try Data(contentsOf: original) == Data(contentsOf: second))
        await #expect(throws: VideoError.destinationExists) {
            try await renderer.render(clipID: clip.id, in: project, at: .zero, to: original)
        }
        await #expect(throws: (any Error).self) {
            try await renderer.render(clipID: clip.id, in: project, at: clip.duration, to: folder.appendingPathComponent("out-of-range.png"))
        }
    }
}
#endif
