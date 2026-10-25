// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
import SwiftVideoTestSupport
@testable import SwiftVideo

@Suite struct AndroidExportTests {
    @Test func fixtureCopiesHaveIndependentContents() throws {
        let first = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let second = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer {
            try? FileManager.default.removeItem(at: first)
            try? FileManager.default.removeItem(at: second)
        }
        try #require(first != second)
        let expected = try Data(contentsOf: second)
        try #require(!expected.isEmpty)

        try Data().write(to: first)

        #expect(try Data(contentsOf: second) == expected)
    }
}

// Share the serialized rendering suite: hosted emulators have limited codec/GPU capacity.
extension RenderBehaviorTests {
    @Test func milestoneExportsRealMedia3Composition() async throws {
        let red = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "red.mp4"))
        let blue = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "blue.mp4"))
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let music = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let one = try VideoTime(value: 1, timescale: 1)
        let two = try VideoTime(value: 2, timescale: 1)
        let half = try VideoTime(value: 1, timescale: 2)
        let quarter = try VideoTime(value: 1, timescale: 4)
        let project = VideoProject(tracks: [
            MediaTrack(name: "Footage", clips: [MediaClip(source: .video(red), duration: one),
                                                MediaClip(source: .video(blue), start: one, duration: one)]),
            MediaTrack(name: "Overlays", clips: [
                MediaClip(source: .text("SWIFT VIDEO", TextStyle(fontSize: 120)), duration: two, zIndex: 2,
                    transform: VisualTransform(y: 0.4, width: 0.6, height: 0.3), animations: [
                        KeyframeAnimation(property: .x, keyframes: [Keyframe(time: .zero, value: 0.3), Keyframe(time: two, value: 0.7)]),
                        KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: half, value: 1)])
                    ]),
                MediaClip(source: .image(image), duration: two, zIndex: 1,
                    transform: VisualTransform(x: 0.85, y: 0.8, width: 0.2, height: 0.2, contentMode: .stretch))
            ]),
            MediaTrack(name: "Music", clips: [MediaClip(source: .audio(music), duration: two,
                                                       audio: AudioSettings(volume: 0.5, fadeIn: quarter, fadeOut: quarter))])
        ])
        let destination = red.deletingLastPathComponent().appendingPathComponent("milestone-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: destination) }
        try await VideoExporter().export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180), videoBitRate: 500_000))
        let first = try Media3TestSupport.frameStats(path: destination.path, timeUs: 500_000)
        let second = try Media3TestSupport.frameStats(path: destination.path, timeUs: 1_500_000)
        #expect(first[0] == 320 && first[1] == 180)
        #expect(abs(first[2] - 2000) < 70)
        #expect(first[3] > 180 && first[5] < 80)
        #expect(second[5] > 180 && second[3] < 80)
        #expect(second[7] > 180 && second[6] < 80 && second[8] < 80)
        #expect(first[9] >= 0 && second[9] > first[9] + first[0] * 0.08)
        let rms = try Media3TestSupport.audioRMS(path: destination.path)
        #expect(rms[1] > 0.05)
        #expect(rms[0] >= 0 && rms[0] < rms[1] * 0.4)
        #expect(rms[2] >= 0 && rms[2] < rms[1] * 0.4)
    }
}
#endif
