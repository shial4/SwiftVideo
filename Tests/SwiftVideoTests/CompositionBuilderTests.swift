// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct CompositionBuilderTests {
    @Test func builderSupportsConditionalRepeatedAndReusableContent() throws {
        let duration = try VideoTime(value: 1, timescale: 1)
        let first = MediaClip.text("Title", duration: duration)
        let captions = ["One", "Two"].map { MediaClip.text($0, duration: duration) }
        let includeTitle = true
        let optional: MediaClip? = first
        let trackID = UUID()
        let project = VideoProject {
            MediaTrack("Titles", id: trackID) {
                if includeTitle { first } else { captions[0] }
                for clip in captions { clip }
            }
            MediaTrack("Reusable") { captions }
            if let optional { MediaTrack("Optional") { optional } }
            if !includeTitle { MediaTrack("Omitted") {} }
        }
        #expect(project.tracks.count == 3)
        #expect(project.tracks[0] == MediaTrack(id: trackID, name: "Titles", clips: [first] + captions))
        #expect(project.tracks[1].clips == captions)
        #expect(project.tracks[2].clips == [first])
        // Duplicated clip IDs across tracks are still rejected by the canonical validator.
        #expect(throws: VideoError.self) { try project.validate() }
    }

    @Test func throwingBuildersPropagateTheOriginalError() {
        enum Failure: Error { case unavailable }
        func missing() throws -> MediaClip { throw Failure.unavailable }
        #expect(throws: Failure.unavailable) {
            try VideoProject { try MediaTrack("Missing") { try missing() } }
        }
    }

    @Test func fluentEditsPreserveIdentityAndTrimmedEffectClock() async throws {
        let duration = try VideoTime(value: 4, timescale: 1)
        let one = try VideoTime(value: 1, timescale: 1)
        let original = MediaClip.video(URL(fileURLWithPath: "/video.mp4"), duration: duration)
            .animate(.opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: duration, value: 1)])
        let editor = try VideoEditor(project: VideoProject { MediaTrack { original } })
        let trimmed = try await editor.apply([.trim(original.id, keeping: VideoTimeRange(start: one, duration: one))])
        let clip = try #require(trimmed.tracks.first?.clips.first)
        let edited = clip.starting(at: .zero).sourceStarting(at: one).zIndex(7)
            .source(.image(URL(fileURLWithPath: "/image.png")))
            .transform(VisualTransform(x: 0.2)).filters([.brightness(0.1)]).filter(.saturation(0))
            .audio(AudioSettings(isMuted: true))
        #expect(edited.id == original.id && edited.effectsOffset == one && edited.effectsDuration == duration)
        #expect(try edited.visualTransform(at: .zero).opacity == 0.25)
        #expect(edited.filters == [.brightness(0.1), .saturation(0)])
        #expect(edited.zIndex == 7 && edited.transform.x == 0.2 && edited.audio.isMuted)
        #expect(edited.sourceStart == one && edited.start == .zero)
        #expect(clip.source == original.source && clip.filters.isEmpty)
        let replaced = edited.animate(.opacity, keyframes: [Keyframe(time: .zero, value: 0.8)])
        #expect(replaced.animations.count == 1)
        #expect(try replaced.visualTransform(at: .zero).opacity == 0.8)
        #expect(replaced.animations([]).animations.isEmpty)
    }

    @Test func factoriesProducePortableValidatedValues() throws {
        let duration = try VideoTime(value: 1, timescale: 1)
        let image = MediaClip.image(URL(fileURLWithPath: "/image.png"), duration: duration)
        let sound = MediaClip.audio(URL(fileURLWithPath: "/sound.wav"), duration: duration)
        let project = VideoProject { MediaTrack("Media") { image; sound } }
        try project.validate()
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project)) == project)
        #expect(image.source.isVisual && !sound.source.isVisual)
    }

    @Test func textRasterUsesLayerBoundsAndRejectsExcessiveAllocation() throws {
        let duration = try VideoTime(value: 1, timescale: 1)
        let clip = MediaClip.text("Caption", duration: duration).transform(VisualTransform(width: 0.5, height: 0.1))
        #expect(try clip.textRasterSize(for: .hd1080) == VideoSize(width: 960, height: 108))
        #expect(try clip.textRasterSize(for: VideoSize(width: 2, height: 2)) == VideoSize(width: 1, height: 1))
        for width in [Double.infinity, .nan, 0, -1, 5] {
            #expect(throws: VideoError.self) {
                try clip.transform(VisualTransform(width: width)).textRasterSize(for: .hd1080)
            }
        }
    }
}
