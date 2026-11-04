// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

extension TimelineTests {
    @Test func speedRetimesClipsGapsAndEffectClocksExactly() throws {
        let second = try VideoTime(value: 1, timescale: 1)
        let four = try VideoTime(value: 4, timescale: 1)
        let clip = MediaClip.video(URL(fileURLWithPath: "/fixture.mp4"), duration: four)
            .starting(at: second).audio(AudioSettings(fadeIn: second))
            .animate(.x, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: four, value: 1)])
        let fast = try clip.speed(.double)
        #expect(fast.id == clip.id && fast.start == clip.start && fast.sourceStart == clip.sourceStart)
        #expect(try fast.sourceDuration == four)
        #expect(fast.duration == (try VideoTime(value: 2, timescale: 1)))
        #expect(fast.audio.fadeIn == (try VideoTime(value: 1, timescale: 2)))
        #expect(try fast.visualTransform(at: second.adding(second)).x == 0.5)
        #expect(try fast.speed(.normal) == clip)

        let later = MediaClip.text("Later", duration: second).starting(at: try VideoTime(value: 7, timescale: 1))
        let track = MediaTrack(clips: [fast, later])
        let slow = try track.speed(.half)
        #expect(slow.id == track.id && slow.clips[0].playbackRate == .double)
        #expect(slow.clips.map(\.start) == (try [second, VideoTime(value: 13, timescale: 1)]))
        #expect(slow.clips[0].duration == four)
        #expect(try slow.speed(.normal) == track)
        let project = VideoProject(tracks: [slow, MediaTrack(clips: [clip])])
        let resolved = try project.renderClips()
        #expect(resolved[0].playbackRate == .normal)
        #expect(resolved[2] == clip)
        #expect(try resolved[0].sourceDuration == four)
        #expect(try MediaTrack().speed(.double).clips.isEmpty)
    }

    @Test func splitAndTrimUseCombinedSourceRateAndRollback() async throws {
        let eight = try VideoTime(value: 8, timescale: 1)
        let one = try VideoTime(value: 1, timescale: 1)
        let clip = try MediaClip.video(URL(fileURLWithPath: "/fixture.mp4"), duration: eight)
            .sourceStarting(at: one).speed(.double)
        let track = try MediaTrack(clips: [clip]).speed(.double)
        let editor = try VideoEditor(project: VideoProject(tracks: [track]))
        let rightID = UUID()
        let split = try await editor.apply([.split(clip.id, at: one, rightID: rightID)])
        #expect(split.tracks[0].clips[1].sourceStart == (try VideoTime(value: 5, timescale: 1)))
        let quarter = try VideoTime(value: 1, timescale: 4)
        let trimmed = try await editor.apply([.trim(rightID, keeping: VideoTimeRange(start: quarter, duration: quarter))])
        #expect(trimmed.tracks[0].clips[1].sourceStart == (try VideoTime(value: 6, timescale: 1)))
        #expect(trimmed.tracks[0].clips[1].effectsOffset == (try VideoTime(value: 5, timescale: 4)))
        let invalid = MediaTrack(id: track.id, clips: trimmed.tracks[0].clips, playbackRate: .quadruple)
        await #expect(throws: VideoError.self) { try await editor.apply([.replaceTrack(invalid)]) }
        #expect(await editor.snapshot() == trimmed)
        let filtered = trimmed.tracks[0].filter(.sepia(0.5))
        let replaced = try await editor.apply([.replaceTrack(filtered)])
        #expect(replaced.tracks == [filtered])
        await #expect(throws: VideoError.self) { try await editor.apply([.replaceTrack(MediaTrack())]) }
    }

    @Test func inheritedFiltersAreOrderedAndDoNotMutateAuthoredClips() throws {
        let one = try VideoTime(value: 1, timescale: 1)
        let video = MediaClip.video(URL(fileURLWithPath: "/fixture.mp4"), duration: one)
            .filter(.brightness(0.1)).audio(AudioSettings().filter(.highPass(cutoffHz: 80)))
        let title = MediaClip.text("Title", duration: one)
        let track = MediaTrack(clips: [video, title]).filter(.contrast(1.2)).filter(.sepia(0.5))
            .audioFilter(.lowPass(cutoffHz: 8_000)).audioFilter(.parametricEQ(frequencyHz: 1_000, gainDB: 3, bandwidthOctaves: 1))
        let project = VideoProject(tracks: [track])
        try project.validate()
        let clips = try project.renderClips()
        #expect(clips[0].filters == video.filters + track.filters)
        #expect(clips[0].audio.filters == video.audio.filters + track.audioFilters)
        #expect(clips[1].audio.filters.isEmpty && clips[1].filters == track.filters)
        #expect(project.tracks[0].clips[0] == video)
        #expect(track.filters([]).filters.isEmpty && track.audioFilters([]).audioFilters.isEmpty)
        let plan = try AndroidRenderPlan(project: project, settings: ExportSettings())
        let planned = try #require(plan.clips.first { $0.id == video.id.uuidString })
        #expect(planned.audioFilters.map(\.kind) == ["highPass", "lowPass", "parametricEQ"])
        #expect(planned.filters.map(\.kind) == ["brightness", "contrast", "sepia"])
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project)) == project)
    }

    @Test func oldProjectsDefaultNewFieldsAndNewProjectsRoundTrip() throws {
        let clip = MediaClip.audio(URL(fileURLWithPath: "/music.wav"), duration: try VideoTime(value: 2, timescale: 1))
        let original = VideoProject(tracks: [MediaTrack(clips: [clip])])
        let encoded = try JSONEncoder().encode(original)
        var object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var track = try #require((object["tracks"] as? [[String: Any]])?.first)
        var item = try #require((track["clips"] as? [[String: Any]])?.first)
        var audio = try #require(item["audio"] as? [String: Any])
        audio.removeValue(forKey: "filters"); item["audio"] = audio; item.removeValue(forKey: "playbackRate")
        track["clips"] = [item]
        for key in ["playbackRate", "filters", "audioFilters"] { track.removeValue(forKey: key) }
        object["tracks"] = [track]
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONSerialization.data(withJSONObject: object)) == original)
        let changed = try VideoProject(tracks: [original.tracks[0].speed(.half).audioFilter(.lowPass(cutoffHz: 500))])
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(changed)) == changed)
    }

    @Test func playbackAndFilterBoundariesRejectInvalidValues() throws {
        for pair: (Int32, Int32) in [(0, 1), (-1, 1), (1, 0), (1, 5), (5, 1)] {
            #expect(throws: VideoError.self) { try PlaybackRate(numerator: pair.0, denominator: pair.1) }
        }
        #expect(try PlaybackRate(numerator: 6, denominator: 4) == PlaybackRate(numerator: 3, denominator: 2))
        #expect(throws: VideoError.self) { try PlaybackRate.quadruple.combined(with: .double) }
        #expect(throws: VideoError.self) { try JSONDecoder().decode(PlaybackRate.self, from: Data(#"{"numerator":8,"denominator":1}"#.utf8)) }
        #expect(try VideoTime.zero.scaled(by: .quarter) == .zero)
        #expect(try VideoTime(value: 3, timescale: 2).scaled(by: PlaybackRate(numerator: 2, denominator: 3)) == VideoTime(value: 1, timescale: 1))
        #expect(throws: VideoError.timeOverflow) { try VideoTime(value: Int64.max, timescale: 1).scaled(by: .double) }
        #expect(throws: VideoError.timeOverflow) { try VideoTime(value: 1, timescale: Int32.max).scaled(by: .half) }
        for filter in [AudioFilter.lowPass(cutoffHz: .nan), .highPass(cutoffHz: 10), .lowPass(cutoffHz: 24_000),
                       .parametricEQ(frequencyHz: 100, gainDB: 25, bandwidthOctaves: 1),
                       .parametricEQ(frequencyHz: 100, gainDB: 0, bandwidthOctaves: 0)] {
            #expect(throws: VideoError.self) { try filter.validate() }
        }
        #expect(throws: VideoError.self) { try AudioFilter.lowPass(cutoffHz: 12_000).validate(sampleRate: 22_050) }
        let clip = MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1)).audio(AudioSettings(filters: [.highPass(cutoffHz: 80)]))
        #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate() }
    }
}
