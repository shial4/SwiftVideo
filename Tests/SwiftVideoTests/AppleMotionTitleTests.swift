// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreImage) && !SWIFTVIDEO_CORE_COVERAGE
import CoreImage
import Foundation
import Metal
import Testing
@testable import SwiftVideo

@Suite struct AppleMotionTitleTests {
    private func time(_ tenths: Int64) throws -> VideoTime { try VideoTime(value: tenths, timescale: 10) }

    private func title(_ text: String, motion: TextMotion) throws -> AppleMotionTitle {
        let style = TextStyle(fontSize: 48)
        let clip = try MediaClip.text(text, duration: time(20), style: style).textMotion(motion)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [clip])])
        try project.validate()
        return try AppleMotionTitle(text: text, style: style, clip: clip, project: project, size: project.canvas)
    }

    @Test func wordsHaveIndependentRastersAndStableLayout() throws {
        let title = try title("ONE TWO", motion: .typewriter(stagger: time(5), unit: .word))
        let first = try pixels(title.image(at: .zero)), both = try pixels(title.image(at: time(5)))
        #expect(first.count > 500 && both.count > first.count * 3 / 2)
        #expect(both.x > first.x + 35)
        #expect(abs(both.x - 160) < 12, "Centered text bounds: \(both)")
    }

    @Test(arguments: ["fi", "e\u{301}👩🏽‍💻"])
    func characterRastersKeepGraphemesAndDisableOptionalLigatures(text: String) throws {
        let title = try title(text, motion: .typewriter(stagger: time(5)))
        let first = try pixels(title.image(at: .zero)), both = try pixels(title.image(at: time(5)))
        #expect(first.count > 40 && both.count > first.count + 40)
        #expect(both.x > first.x + 3)
    }

    @Test func customUnitTransformsMoveCachedGlyphsOnTheGPU() throws {
        let motion = try TextMotion(animations: [KeyframeAnimation(property: .x, keyframes: [
            Keyframe(time: .zero, value: 0.2), Keyframe(time: time(4), value: 0)
        ])])
        let title = try title("TITLE", motion: motion)
        let initial = try pixels(title.image(at: .zero)), settled = try pixels(title.image(at: time(4)))
        #expect(abs(initial.x - settled.x - 64) < 1)
        #expect(abs(initial.count - settled.count) < 10)
        let fade = try self.title("TITLE", motion: .fadeUp(duration: time(4)))
        #expect(try pixels(fade.image(at: .zero)).count == 0)
        #expect(try pixels(fade.image(at: time(4))).count > 500)
    }

    private func pixels(_ image: CIImage) throws -> (count: Int, x: Double) {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let ci = CIContext(mtlDevice: device)
        let cg = try #require(ci.createCGImage(image, from: image.extent))
        var bytes = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
        try bytes.withUnsafeMutableBytes { data in
            let context = try #require(CGContext(data: data.baseAddress, width: cg.width, height: cg.height,
                bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
        }
        var count = 0, xSum = 0
        for y in 0..<cg.height {
            for x in 0..<cg.width where bytes[(y * cg.width + x) * 4 + 3] > 128 { count += 1; xSum += x }
        }
        return (count, count == 0 ? 0 : Double(xSum) / Double(count))
    }
}
#endif
