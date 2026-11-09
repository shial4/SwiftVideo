// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
import SwiftVideoTestSupport
@testable import SwiftVideo

@Suite struct AndroidExportTests {
    @Test(arguments: [Int64(1_000_000), Int64(2_000_000)])
    func cancellationBeforeFirstVideoSampleClosesTheMuxer(durationUs: Int64) throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("empty-muxer-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        try Media3TestSupport.closeEmptyTimelineMuxer(path: output.path, durationUs: durationUs)
        #expect(try Data(contentsOf: output).isEmpty, "Cancellation before the first sample should leave an empty staging file.")
    }

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
    @Test(arguments: [30, 40])
    func singleFrameExportHasDurationAndDecodes(timescale: Int32) async throws {
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let output = source.deletingLastPathComponent().appendingPathComponent("single-frame-\(UUID()).mp4")
        defer {
            try? FileManager.default.removeItem(at: source)
            try? FileManager.default.removeItem(at: output)
        }
        let duration = try VideoTime(value: 1, timescale: timescale)
        let size = VideoSize(width: 320, height: 180)
        let project = VideoProject(canvas: size, tracks: [MediaTrack(clips: [
            MediaClip(source: .image(source), duration: duration)
        ])])
        try await VideoExporter().export(project, to: output,
            settings: ExportSettings(resolution: size, videoBitRate: 500_000))
        let frame = try Media3TestSupport.frameStats(path: output.path, timeUs: 0)
        #expect(frame[0] == 320 && frame[1] == 180)
        #expect(abs(frame[2] - duration.seconds * 1000) <= 1,
                "A one-frame MP4 must retain its requested duration: \(frame[2]) ms")
        #expect(frame[4] > 180 && frame[3] < 80 && frame[5] < 80,
                "The one-frame MP4 must decode its image: \(Array(frame[3...5]))")
    }

    @Test(arguments: [PlaybackRate.quarter, .half, .double, .quadruple])
    func media3SpeedPreservesPitchAndDuration(rate: PlaybackRate) async throws {
        let music = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let video = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "blue.mp4"))
        let destination = music.deletingLastPathComponent().appendingPathComponent("speed-\(UUID()).mp4")
        defer { for url in [music, video, destination] { try? FileManager.default.removeItem(at: url) } }
        let one = try VideoTime(value: 1, timescale: 1)
        let clip = try MediaClip.audio(music, duration: one).speed(rate)
        let visual = try MediaClip.video(video, duration: one).speed(rate)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [clip, visual])])
        try await VideoExporter().export(project, to: destination)
        let stats = try Media3TestSupport.audioStats(path: destination.path, duration: clip.duration.seconds)
        #expect(abs(stats[3] - 440) < 15, "\(rate.multiplier)x pitch: \(stats[3]) Hz")
        #expect(stats[0] > 0.05 && stats[1] > 0.05 && stats[2] > 0.05, "Audio edges: \(stats)")
        let frame = try Media3TestSupport.frameStats(path: destination.path, timeUs: Int64(clip.duration.seconds * 500_000))
        #expect(abs(frame[2] / 1000 - clip.duration.seconds) < 0.07)
        #expect(frame[5] > 180)
    }

    @Test(arguments: [125, 250, 375], [false, true])
    func trimmedPCMKeepsItsStartAndFadeClock(startMilliseconds: Int, floating: Bool) async throws {
        let music = floating ? try floatPCMFixture() : URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer { for url in [music, image] { try? FileManager.default.removeItem(at: url) } }
        let audio = try MediaClip.audio(music, duration: VideoTime(value: 1, timescale: 1))
            .sourceStarting(at: VideoTime(value: Int64(startMilliseconds), timescale: 1000))
            .audio(AudioSettings(volume: 0.5, fadeOut: VideoTime(value: 1, timescale: 4))).speed(.half)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [
            audio, MediaClip.image(image, duration: try VideoTime(value: 5, timescale: 2))
        ])])
        // The original Media3 failure depended on initial seek/load scheduling.
        for _ in 0..<2 {
            let output = music.deletingLastPathComponent().appendingPathComponent("pcm-trim-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: output) }
            try await VideoExporter().export(project, to: output)
            let stats = try Media3TestSupport.audioStats(path: output.path, duration: 2)
            #expect(stats[1] > 0.1)
            #expect(stats[0] > stats[1] * 0.5, "A trimmed clip must start without an added PCM packet gap: \(stats)")
            #expect(stats[2] < stats[1] * 0.16, "The fade must end on the retimed clip's timeline: \(stats)")
            #expect(abs(stats[3] - 440) < 15)
        }
    }

    @Test func cancellingPCMPreparationCleansUpAndAllowsAnotherExport() async throws {
        let music = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pcm-cancellation-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { for url in [music, folder] { try? FileManager.default.removeItem(at: url) } }
        let clip = try MediaClip.audio(music, duration: VideoTime(value: 1, timescale: 1))
            .sourceStarting(at: VideoTime(value: 1, timescale: 4))
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [clip])])
        let exporter = VideoExporter()
        let output = folder.appendingPathComponent("output.mp4")
        let (events, continuation) = AsyncStream<ExportProgress>.makeStream()
        let task = Task { try await exporter.export(project, to: output) { continuation.yield($0) } }
        var iterator = events.makeAsyncIterator()
        while let event = await iterator.next() { if event.phase == .preparing { break } }
        await exporter.cancel()
        await #expect(throws: VideoError.cancelled) { try await task.value }
        continuation.finish()
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        try await exporter.export(project, to: output)
        #expect(try Data(contentsOf: output).count > 0)
    }

    @Test func failedPCMPreparationRemovesPartialFilesAndRecovers() async throws {
        let music = try floatPCMFixture()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("pcm-failure-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { for url in [music, folder] { try? FileManager.default.removeItem(at: url) } }
        let clip = MediaClip.audio(music, duration: try VideoTime(value: 1, timescale: 1))
        let unavailable = try clip.sourceStarting(at: VideoTime(value: 3, timescale: 2))
        let exporter = VideoExporter()
        let output = folder.appendingPathComponent("output.mp4")
        await #expect(throws: VideoError.self) {
            try await exporter.export(VideoProject(canvas: VideoSize(width: 320, height: 180),
                tracks: [MediaTrack(clips: [unavailable])]), to: output)
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
        let available = try clip.sourceStarting(at: VideoTime(value: 1, timescale: 4))
        try await exporter.export(VideoProject(canvas: VideoSize(width: 320, height: 180),
            tracks: [MediaTrack(clips: [available])]), to: output)
        #expect(try Data(contentsOf: output).count > 0)
    }

    private func floatPCMFixture() throws -> URL {
        let rate = 44_100, frames = rate * 2
        var data = Data()
        func word(_ value: UInt32, bytes: Int = 4) {
            for index in 0..<bytes { data.append(UInt8(truncatingIfNeeded: value >> (index * 8))) }
        }
        data.append(contentsOf: "RIFF".utf8); word(UInt32(frames * 4 + 36))
        data.append(contentsOf: "WAVEfmt ".utf8); word(16)
        word(3, bytes: 2); word(1, bytes: 2); word(UInt32(rate)); word(UInt32(rate * 4))
        word(4, bytes: 2); word(32, bytes: 2)
        data.append(contentsOf: "data".utf8); word(UInt32(frames * 4))
        for frame in 0..<frames { word(Float(0.6 * sin(2 * .pi * 440 * Double(frame) / Double(rate))).bitPattern) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("float-pcm-\(UUID()).wav")
        try data.write(to: url)
        return url
    }

    @Test func media3ClipAndTrackEQProcessOrderedBands() async throws {
        let music = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        defer { try? FileManager.default.removeItem(at: music) }
        let cases: [[AudioFilter]] = [[], [.lowPass(cutoffHz: 100)], [.highPass(cutoffHz: 2_000)],
                                    [.parametricEQ(frequencyHz: 440, gainDB: -12, bandwidthOctaves: 1)],
                                    [.parametricEQ(frequencyHz: 23_999, gainDB: -12, bandwidthOctaves: 5)]]
        var levels: [Double] = []
        for filters in cases {
            let clip = MediaClip.audio(music, duration: try VideoTime(value: 1, timescale: 1))
                .audio(AudioSettings(filters: [.highPass(cutoffHz: 40)]))
            let track = MediaTrack(clips: [clip]).audioFilters(filters)
            let destination = music.deletingLastPathComponent().appendingPathComponent("eq-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: destination) }
            try await VideoExporter().export(VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [track]), to: destination)
            levels.append(try Media3TestSupport.audioStats(path: destination.path, duration: 1)[4])
        }
        #expect(levels[0] > 0.1)
        #expect(levels[1] < levels[0] * 0.15 && levels[2] < levels[0] * 0.15)
        #expect(levels[3] < levels[0] * 0.35)
        #expect(levels[4] > levels[0] * 0.15 && levels[4] < levels[0] * 0.35, "Wide near-Nyquist bands must stay finite")
    }

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
