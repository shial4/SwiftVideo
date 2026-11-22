// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct TextMotionTests {
    private func time(_ tenths: Int64) throws -> VideoTime { try VideoTime(value: tenths, timescale: 10) }

    @Test func textUnitsPreserveUnicodeGraphemesAndWhitespaceLayout() throws {
        let text = "Hi 👩🏽‍💻 e\u{301}"
        let characters = TextMotion.typewriter(stagger: .zero)
        let words = TextMotion.typewriter(stagger: .zero, unit: .word)
        #expect(characters.ranges(in: text) == [.init(start: 0, length: 1), .init(start: 1, length: 1),
            .init(start: 3, length: 7), .init(start: 11, length: 2)])
        #expect(words.ranges(in: text) == [.init(start: 0, length: 2), .init(start: 3, length: 7), .init(start: 11, length: 2)])
        #expect(words.ranges(in: "  First\n\tsecond  ") == [.init(start: 2, length: 5), .init(start: 9, length: 6)])
    }

    @Test func presetsRespectStaggerAndCustomAnimationsUseTheSharedSampler() throws {
        let typewriter = try TextMotion.typewriter(stagger: time(1))
        #expect(try typewriter.transform(forUnit: 2, at: time(1)).opacity == 0)
        #expect(try typewriter.transform(forUnit: 2, at: time(2)).opacity == 1)
        let fade = try TextMotion.fadeUp(duration: time(4), stagger: time(2), distance: 0.2)
        let halfway = try fade.transform(forUnit: 1, at: time(4))
        #expect(halfway.opacity == 0.5 && abs(halfway.y - 0.05) < 1e-9)
        #expect(try fade.transform(forUnit: 1, at: time(6)).y == 0)
        let pop = try TextMotion.pop(duration: time(4))
        #expect(try pop.transform(forUnit: 0, at: time(3)).scale == 1.08)
        #expect(try pop.transform(forUnit: 0, at: time(4)).scale == 1)
        let animation = try KeyframeAnimation(property: .rotation, keyframes: [Keyframe(time: .zero, value: 0),
            Keyframe(time: time(2), value: 90)], repetition: .forever(autoreverses: true))
        let custom = TextMotion(stagger: .zero, animations: [animation])
        #expect(abs(try custom.transform(forUnit: 0, at: time(3)).rotation - 45) < 1e-9)
        #expect(throws: VideoError.self) { try custom.transform(forUnit: -1, at: .zero) }
    }

    @Test func motionRoundTripsRetimesAndSurvivesTrimAndSplit() async throws {
        let motion = try TextMotion.fadeUp(duration: time(4), stagger: time(2))
        let clip = try MediaClip.text("First second", duration: time(20)).textMotion(motion).speed(.double)
        let retimed = try #require(clip.textMotion)
        #expect(try retimed.stagger == time(1))
        #expect(try retimed.transform(forUnit: 1, at: time(2)) == motion.transform(forUnit: 1, at: time(4)))
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [clip])]))
        _ = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: time(1), duration: time(8)))])
        let edited = try await editor.apply([.split(clip.id, at: time(4), rightID: UUID())])
        #expect(edited.tracks[0].clips.allSatisfy { $0.textMotion == retimed })
        #expect(try edited.tracks[0].clips[1].effectsOffset == time(4))
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(edited)) == edited)
        #expect(clip.textMotion(nil).textMotion == nil)
        let limited = RendererCapabilities(name: "Static titles", features: Set(CompositionFeature.allCases).subtracting([.motionTitles]),
            codecs: [.h264], containers: [.mp4])
        #expect(throws: VideoError.unsupportedFeature("Static titles does not support: motionTitles.")) {
            try limited.validate(edited, settings: ExportSettings())
        }
    }

    @Test func invalidMotionIsRejectedBeforeRendering() throws {
        func validate(_ text: String, _ motion: TextMotion) throws {
            let clip = try MediaClip.text(text, duration: time(10)).textMotion(motion)
            try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate()
        }
        #expect(throws: VideoError.self) { try validate("   ", .typewriter(stagger: .zero)) }
        #expect(throws: VideoError.self) { try validate(String(repeating: "x", count: 129), .typewriter(stagger: .zero)) }
        #expect(throws: VideoError.self) { try validate("AB", .typewriter(stagger: time(-1))) }
        #expect(throws: VideoError.self) { try validate("ABCD", .typewriter(stagger: time(4))) }
        #expect(throws: VideoError.self) { try validate("Two words", .fadeUp(duration: time(8), stagger: time(3))) }
        #expect(throws: VideoError.self) { try validate("Title", .pop(duration: .zero)) }
        let audio = try MediaClip.audio(URL(fileURLWithPath: "/unused.wav"), duration: time(10))
            .textMotion(.typewriter(stagger: .zero))
        #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [audio])]).validate() }
    }
}
