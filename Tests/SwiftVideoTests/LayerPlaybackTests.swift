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

    private func center(_ url: URL) throws -> [Int] {
        #if os(Android)
        let stats = try Media3TestSupport.layerImageStats(path: url.path)
        try #require(stats.count == 10)
        return Array(stats[6...8])
        #else
        let image = try #require(CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) })
        let context = try #require(CGContext(data: nil, width: 160, height: 90, bitsPerComponent: 8, bytesPerRow: 640,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.draw(image, in: CGRect(x: 0, y: 0, width: 160, height: 90))
        let bytes = try #require(context.data).assumingMemoryBound(to: UInt8.self)
        return (0..<3).map { Int(bytes[(45 * 160 + 80) * 4 + $0]) }
        #endif
    }
}
#endif
