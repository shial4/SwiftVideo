// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

private func seconds(_ value: Int64) throws -> VideoTime { try VideoTime(value: value, timescale: 1) }

@Suite struct TimelineTests {
    @Test func rationalTimePreservesNTSCFrames() throws {
        let rate = try FrameRate(numerator: 30_000, denominator: 1_001)
        let frame = try VideoTime(frames: 1, rate: rate)
        let ten = try (0..<10).reduce(VideoTime.zero) { value, _ in try value.adding(frame) }
        #expect(ten == (try VideoTime(frames: 10, rate: rate)))
        #expect(try VideoTime(value: 2, timescale: 4) == VideoTime(value: 1, timescale: 2))
    }

    @Test func comparisonDoesNotOverflow() throws {
        let large = try VideoTime(value: Int64.max - 1, timescale: 3)
        let smaller = try VideoTime(value: Int64.max - 1, timescale: 4)
        #expect(smaller < large)
        let maximum = try VideoTime(value: Int64.max, timescale: 1)
        #expect(throws: VideoError.timeOverflow) { try maximum.adding(maximum) }
    }

    @Test func decodingRejectsInvalidTime() throws {
        let bytes = Data(#"{"value":1,"timescale":0}"#.utf8)
        #expect(throws: VideoError.self) { try JSONDecoder().decode(VideoTime.self, from: bytes) }
    }

    @Test func clipsUseHalfOpenIntervalsAndStableZOrder() throws {
        let first = MediaClip(source: .text("A", TextStyle()), duration: try seconds(2), zIndex: 2)
        let second = MediaClip(source: .text("B", TextStyle()), duration: try seconds(2), zIndex: 1)
        let third = MediaClip(source: .text("C", TextStyle()), duration: try seconds(2), zIndex: 2)
        let project = VideoProject(tracks: [MediaTrack(clips: [first, second]), MediaTrack(clips: [third])])
        #expect(try project.visualClips(at: .zero).map(\.id) == [second.id, first.id, third.id])
        #expect(try project.visualClips(at: seconds(2)).isEmpty)
    }

    @Test func failedBatchRollsBackEveryEdit() async throws {
        let track = MediaTrack()
        let project = VideoProject(tracks: [track])
        let editor = try VideoEditor(project: project)
        let clip = MediaClip(source: .text("A", TextStyle()), duration: try seconds(2))
        await #expect(throws: VideoError.self) {
            try await editor.apply([.addClip(clip, trackID: track.id), .offset(clip.id, by: seconds(-1))])
        }
        #expect(await editor.snapshot() == project)
    }

    @Test func splitPreservesSourceAnimationAndAudioClock() async throws {
        let animation = KeyframeAnimation(property: .x, keyframes: [
            Keyframe(time: .zero, value: 0), Keyframe(time: try seconds(10), value: 1)
        ])
        let clip = MediaClip(source: .video(URL(fileURLWithPath: "/fixture.mov")), duration: try seconds(10),
                             sourceStart: try seconds(2), animations: [animation],
                             audio: AudioSettings(fadeIn: try seconds(4), fadeOut: try seconds(2)))
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [clip])]))
        let rightID = UUID()
        let edited = try await editor.apply([.split(clip.id, at: seconds(3), rightID: rightID)])
        let right = try #require(edited.tracks.first?.clips.last)
        #expect(right.id == rightID)
        #expect(right.sourceStart == (try seconds(5)))
        #expect(try right.visualTransform(at: seconds(4)) == clip.visualTransform(at: seconds(4)))
        #expect(try right.audioGain(at: seconds(3)) == clip.audioGain(at: seconds(3)))
        #expect(try edited.duration == seconds(10))
    }

    @Test func trimAndOffsetPreserveEffects() async throws {
        let clip = MediaClip(source: .audio(URL(fileURLWithPath: "/music.wav")), duration: try seconds(10),
                             audio: AudioSettings(fadeIn: try seconds(4)))
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [clip])]))
        let edited = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: seconds(2), duration: seconds(5))),
                                             .offset(clip.id, by: seconds(1))])
        let trimmed = try #require(edited.tracks.first?.clips.first)
        #expect(trimmed.start == (try seconds(3)))
        #expect(trimmed.sourceStart == (try seconds(2)))
        #expect(try trimmed.audioGain(at: seconds(3)) == 0.5)
    }

    @Test func mergePlacesClipsConsecutively() async throws {
        let track = MediaTrack()
        let editor = try VideoEditor(project: VideoProject(tracks: [track]))
        let clips = try [2, 3].map { MediaClip(source: .text("Clip", TextStyle()), duration: try seconds(Int64($0))) }
        let project = try await editor.apply([.mergeSequentially(clips, trackID: track.id, start: seconds(1))])
        #expect(project.tracks[0].clips.map(\.start) == (try [seconds(1), seconds(3)]))
        #expect(try project.duration == seconds(6))
    }

    @Test func serializationRoundTripPreservesProject() throws {
        let clip = MediaClip(source: .text("Title", TextStyle(shadow: TextShadow())), duration: try seconds(2),
                             filters: [.saturation(0.5)], animations: [KeyframeAnimation(property: .opacity, keyframes: [
                                Keyframe(time: .zero, value: 0), Keyframe(time: try seconds(1), value: 1, easing: .easeOut)
                             ])])
        let project = VideoProject(tracks: [MediaTrack(clips: [clip])])
        let restored = try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project))
        try restored.validate()
        #expect(restored == project)
    }

    @Test func invalidAnimationAndDuplicateIdentityAreRejected() throws {
        let time = try seconds(1)
        let clip = MediaClip(source: .text("A", TextStyle()), duration: time, animations: [
            KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: time, value: 0), Keyframe(time: time, value: 1)])
        ])
        #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate() }
        let valid = MediaClip(source: .text("B", TextStyle()), duration: time)
        #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [valid, valid])]).validate() }
    }
}
