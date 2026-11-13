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

@Suite(.serialized) struct MotionTitleRenderTests {
    private func time(_ tenths: Int64) throws -> VideoTime { try VideoTime(value: tenths, timescale: 10) }

    @Test(arguments: ["ONE TWO", "fi", "e\u{301}👩🏽‍💻"])
    func unitsAppearIndependentlyWithoutChangingLayout(text: String) async throws {
        let motion = try TextMotion.typewriter(stagger: time(5), unit: text == "ONE TWO" ? .word : .character)
        let clip = try MediaClip.text(text, duration: time(10), style: TextStyle(fontSize: 48)).textMotion(motion)
        try await withExport(clips: [clip]) { url in
            let first = try await stats(url, at: 0.1), both = try await stats(url, at: 0.7)
            #expect(first[0] > 40 && both[0] > first[0] + 30, "Independent units: \(first), \(both)")
            #expect(both[1] > first[1] + 3, "Text must retain its measured horizontal layout.")
            #expect(first[2] < 70 && both[2] < 70, "Titles should stay at the top of their canvas: \(both)")
        }
    }

    @Test func fadeUpUsesTransparentGlyphsAndGPUTranslation() async throws {
        let clip = try MediaClip.text("TITLE", duration: time(10), style: TextStyle(fontSize: 48))
            .textMotion(.fadeUp(duration: time(4), distance: 0.2))
        try await withExport(clips: [clip]) { url in
            let hidden = try await stats(url, at: 0), half = try await stats(url, at: 0.2), settled = try await stats(url, at: 0.6)
            #expect(hidden[0] == 0)
            #expect(half[0] > 200 && settled[0] > 400)
            #expect(half[2] - settled[2] > 5 && half[2] - settled[2] < 15, "Downward offset: \(half), \(settled)")
            #expect(half[3] > 100 && half[3] < 210 && half[5] > 220, "Half-white over blue should retain both contributions: \(half)")
            #expect(settled[3] > 220 && settled[4] > 220)
        }
    }

    @Test func retimingTrimmingAndSplittingPreserveTitleProgress() async throws {
        let clip = try MediaClip.text("I I I", duration: time(20), style: TextStyle(fontSize: 48))
            .textMotion(.typewriter(stagger: time(6), unit: .word)).speed(.double)
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [clip])]))
        _ = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: time(1), duration: time(8)))])
        let edited = try await editor.apply([.split(clip.id, at: time(4), rightID: UUID())])
        try await withExport(clips: edited.tracks[0].clips) { url in
            let first = try await stats(url, at: 0.2), second = try await stats(url, at: 0.5), third = try await stats(url, at: 0.7)
            #expect(first[0] > 70 && second[0] > first[0] * 1.5 && third[0] > second[0] * 1.25,
                "Progress must survive the split: \(first), \(second), \(third)")
        }
    }

    @Test func customUnitRotationAndScaleChangeEncodedGeometry() async throws {
        let motion = try TextMotion(animations: [
            KeyframeAnimation(property: .y, keyframes: [Keyframe(time: .zero, value: 0.4)]),
            KeyframeAnimation(property: .rotation, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: time(4), value: 90)]),
            KeyframeAnimation(property: .scale, keyframes: [Keyframe(time: .zero, value: 0.5), Keyframe(time: time(4), value: 1)])
        ])
        let clip = try MediaClip.text("TITLE", duration: time(10), style: TextStyle(fontSize: 48)).textMotion(motion)
        try await withExport(clips: [clip]) { url in
            let small = try await stats(url, at: 0), rotated = try await stats(url, at: 0.6)
            #expect(small[6] > small[7] * 2 && rotated[7] > rotated[6] * 2, "Rotation swaps the long axis: \(small), \(rotated)")
            #expect(rotated[0] > small[0] * 3 && rotated[0] < small[0] * 5, "Doubling scale should quadruple ink area.")
        }
    }

    @Test func wrappedWordsRetainSelectedFontAndIndependentShadows() async throws {
        #if os(Android)
        let font = "monospace"
        #else
        let font = "Courier"
        #endif
        let motion = try TextMotion.typewriter(stagger: time(5), unit: .word)
        let plain = try MediaClip.text("WIDE WIDE", duration: time(10), style: TextStyle(fontName: font, fontSize: 48))
            .textMotion(motion).transform(VisualTransform(width: 0.5))
        let shadow = try MediaClip.text("WIDE WIDE", duration: time(10),
            style: TextStyle(fontName: font, fontSize: 48, shadow: TextShadow(color: .white, radius: 1, x: 6, y: 8)))
            .textMotion(motion).transform(VisualTransform(width: 0.5)).starting(at: time(10))
        try await withExport(clips: [plain, shadow]) { url in
            let first = try await stats(url, at: 0.1), both = try await stats(url, at: 0.7)
            let shadowFirst = try await stats(url, at: 1.1), shadowBoth = try await stats(url, at: 1.7)
            #expect(first[0] > 300 && both[0] > first[0] * 1.7)
            #expect(both[2] > first[2] + 15, "The second word must wrap to a lower line.")
            #expect(shadowFirst[0] > first[0] * 1.2 && shadowBoth[0] > shadowFirst[0] * 1.7,
                "Only revealed words should contribute their shadows: \(first), \(shadowFirst), \(shadowBoth)")
        }
    }

    private func withExport(clips: [MediaClip], inspect: (URL) async throws -> Void) async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("motion-title-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), background: VideoColor(red: 0, green: 0, blue: 1),
            tracks: [MediaTrack(clips: clips)])
        let url = folder.appendingPathComponent("title.mp4")
        try await VideoExporter().export(project, to: url)
        try await inspect(url)
    }

    private func stats(_ url: URL, at seconds: Double) async throws -> [Double] {
        #if os(Android)
        return try Media3TestSupport.titleStats(path: url.path, timeUs: Int64((seconds * 1_000_000).rounded()))
        #else
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(data: buffer.baseAddress, width: image.width, height: image.height,
                bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        var count = 0.0, xSum = 0.0, ySum = 0.0
        var red: UInt8 = 0, green: UInt8 = 0, blue: UInt8 = 0
        var minX = image.width, maxX = -1, minY = image.height, maxY = -1
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4, r = bytes[offset], g = bytes[offset + 1]
                if r > 70 && g > 70 {
                    count += 1; xSum += Double(x); ySum += Double(y)
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
                if r > red { red = r; green = g; blue = bytes[offset + 2] }
            }
        }
        return [count, count > 0 ? xSum / count : -1, count > 0 ? ySum / count : -1, Double(red), Double(green), Double(blue),
                Double(max(0, maxX - minX + 1)), Double(max(0, maxY - minY + 1))]
        #endif
    }
}
#endif
