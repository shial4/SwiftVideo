// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import Foundation
import Testing
import SwiftVideoTestSupport
@testable import SwiftVideo

extension RenderBehaviorTests {
    @Test(arguments: [Int64(0), 1000], [Int64(0), 250])
    func continuousVideoPreviewCrossesInitialGap(startMilliseconds: Int64, sourceStartMilliseconds: Int64) async throws {
        let video = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "red.mp4"))
        defer { try? FileManager.default.removeItem(at: video) }
        let duration = try VideoTime(value: 500, timescale: 1000)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180),
            background: VideoColor(red: 0, green: 0, blue: 1), tracks: [
                MediaTrack(clips: [MediaClip(source: .video(video),
                    start: try VideoTime(value: startMilliseconds, timescale: 1000), duration: duration,
                    sourceStart: try VideoTime(value: sourceStartMilliseconds, timescale: 1000))])
            ])
        let settings = ExportSettings(resolution: project.canvas, frameRate: .fps30)
        let json = try AndroidVideoRenderer.serializedPlan(project, settings: settings)
        let probe = Media3PreviewProbe()
        defer { probe.release() }
        try probe.start(json: json, sample: AndroidRenderPlan.visualSampler(for: project))
        probe.play()
        var sawVideo = false
        var sawEarlyVideo = false
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while ContinuousClock.now < deadline {
            try #require(probe.status() >= 0, "Continuous preview failed: \(probe.failureMessage())")
            let position = probe.positionMilliseconds()
            let pixels = probe.pixels()
            if probe.frameCount() > 0, pixels.count == 6, pixels[0] > 210, pixels[2] < 40 {
                sawVideo = true
                sawEarlyVideo = sawEarlyVideo || position + 100 < startMilliseconds
            }
            if position >= startMilliseconds + 500 && !probe.isPlaying() { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(!sawEarlyVideo, "The video must remain hidden until its timeline start")
        #expect(sawVideo, "Continuous playback never displayed the video: start \(startMilliseconds), source trim \(sourceStartMilliseconds), position \(probe.positionMilliseconds()), pixels \(probe.pixels()), frames \(probe.frameCount())")
        #expect(probe.positionMilliseconds() >= startMilliseconds + 500 && !probe.isPlaying())
    }

    @Test func nativePreviewValidatesAndReleasesWithoutAnAttachedSurface() async throws {
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer { try? FileManager.default.removeItem(at: image) }
        let duration = try VideoTime(value: 1, timescale: 1)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [
            MediaTrack(clips: [MediaClip(source: .image(image), duration: duration)])
        ])
        #expect(throws: VideoError.self) {
            try AndroidVideoPreview(project: project, settings: ExportSettings(container: .mov))
        }
        #expect(throws: VideoError.self) {
            try AndroidVideoPreview(project: VideoProject(canvas: project.canvas), settings: ExportSettings())
        }
        var preview: AndroidVideoPreview? = try AndroidVideoPreview(project: project, settings: ExportSettings())
        let session = try #require(preview?.session)
        defer { session.release() }
        session.seek(milliseconds: 500)
        session.play()
        session.pause()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.currentStatus() == 1 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(session.currentStatus() == 2, "Preparation failed: \(session.failureMessage())")
        #expect(session.positionMilliseconds() == 500)
        #expect(!session.isPlaying())
        let directory = session.temporaryDirectoryPath()
        try #require(FileManager.default.fileExists(atPath: directory))
        preview = nil // The native owner's deinit must release the platform session.
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while session.currentStatus() != 3 && ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(session.currentStatus() == 3)
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    @Test func legacyAACPrimingLeavesExplicitUnknownAndMalformedSourcesAlone() throws {
        let names = ["red-with-music.mp4", "red-with-offset-music.mp4", "music.m4a"]
        let sources = try names.map { URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: $0)) }
        let changed = sources[0].deletingLastPathComponent().appendingPathComponent("priming-control-\(UUID()).mp4")
        defer { for url in sources + [changed] { try? FileManager.default.removeItem(at: url) } }
        #expect(Media3AudioCacheProbe.legacyTiming(source: sources[0].absoluteString, trackID: 2, profile: 2)
                == [2112, 192, 0, 2_000_000])
        #expect(Media3AudioCacheProbe.legacyTiming(source: sources[1].absoluteString, trackID: 2, profile: 2)
                == [2112, 192, 250_000, 2_250_000])
        #expect(Media3AudioCacheProbe.legacyTiming(source: sources[2].absoluteString, trackID: 1, profile: 2).isEmpty)
        #expect(Media3AudioCacheProbe.legacyTiming(source: sources[0].absoluteString, trackID: 1, profile: 2).isEmpty)
        #expect(Media3AudioCacheProbe.legacyTiming(source: sources[0].absoluteString, trackID: 2, profile: 5).isEmpty)
        let original = try Data(contentsOf: sources[0])
        let handler = try #require(original.range(of: Data("Core Media Audio".utf8)))
        var foreign = original
        foreign[handler.lowerBound] = 88 // An unknown handler must not inherit Apple's convention.
        let audioTable = try #require(original.range(of: Data("stco".utf8), in: handler.upperBound..<original.endIndex))
        var grouped = original
        grouped.replaceSubrange(audioTable, with: Data("sgpd".utf8))
        // Even an unrecognized or malformed sample group disables implicit timing.
        var oversized = original
        oversized.replaceSubrange(0..<4, with: [0x7f, 0xff, 0xff, 0xff])
        let edit = try #require(original.range(of: Data("elst".utf8), options: .backwards))
        var trimmed = original
        // Shorten the media edit to 1.5 seconds; the discarded audio is not padding.
        trimmed.replaceSubrange((edit.lowerBound + 12)..<(edit.lowerBound + 16), with: [0, 0, 3, 132])
        var shifted = original
        shifted[edit.lowerBound + 19] = 1 // A nonzero media start requires a different edit policy.
        for data in [foreign, grouped, oversized, trimmed, shifted, original.dropLast(10)] {
            try Data(data).write(to: changed)
            #expect(Media3AudioCacheProbe.legacyTiming(source: changed.absoluteString, trackID: 2, profile: 2).isEmpty)
        }
        #expect(try Data(contentsOf: sources[0]) == original)
    }

    @Test func previewReleaseDuringPreparationRemovesTemporaryAudio() async throws {
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let audio = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.m4a"))
        defer { for url in [image, audio] { try? FileManager.default.removeItem(at: url) } }
        let duration = try VideoTime(value: 2, timescale: 1)
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [
            MediaTrack(clips: [MediaClip(source: .image(image), duration: duration)]),
            MediaTrack(clips: [MediaClip(source: .audio(audio), duration: duration)])
        ])
        let plan = try AndroidRenderPlan(project: project, settings: ExportSettings(resolution: project.canvas))
        let json = try #require(String(data: JSONEncoder().encode(plan), encoding: .utf8))
        let probe = Media3PreviewProbe()
        defer { probe.release() }
        try probe.start(json: json, sample: AndroidRenderPlan.visualSampler(for: project))
        probe.release()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.status() != 3 && ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(probe.status() == 3)
        let directory = probe.temporaryDirectoryPath()
        try #require(!directory.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: directory))
    }

    @Test(arguments: AACFixtureReference.all)
    func previewAudioCacheReusesSourcesAndCleansFailedWrites(reference: AACFixtureReference) throws {
        let fixture = reference.name
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: fixture))
        let root = source.deletingLastPathComponent().appendingPathComponent("audio-cache-test-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: root) }
        let original = try Data(contentsOf: source)
        let success = root.appendingPathComponent("success")
        try FileManager.default.createDirectory(at: success, withIntermediateDirectories: true)
        let paths = try Media3AudioCacheProbe.prepare(source: source.absoluteString, directory: success.path,
            maximumBytes: 64 * 1024 * 1024, cancelAfterCheck: 0)
        try #require(paths.count == 3 && Set(paths).count == 1)
        let decoded = try #require(URL(string: paths[0]))
        #expect(try FileManager.default.contentsOfDirectory(atPath: success.path) == [decoded.lastPathComponent])
        let sound = try Media3TestSupport.audioRMS(path: decoded.path)
        let offsetFrames = reference.offsetFrames
        #expect(abs(sound[0] - (offsetFrames == 0 ? AACFixtureReference.initialRMS : 0)) < 0.01,
                "\(fixture): decoded PCM must preserve the source track's initial audio or silence")
        #expect(abs(sound[1] - reference.middleRMS) < 0.001)
        let wave = try Data(contentsOf: decoded)
        #expect(wave.count == 44 + (96_000 + offsetFrames) * 4,
                "\(fixture): the cache must remove AAC priming and padding without losing source frames")
        if offsetFrames > 0 {
            #expect(wave[44..<(44 + offsetFrames * 4)].allSatisfy { $0 == 0 })
            var squares = 0.0
            for frame in offsetFrames..<(offsetFrames + 2400) {
                let index = 44 + frame * 4
                let bits = UInt16(wave[index]) | UInt16(wave[index + 1]) << 8
                let value = Double(Int16(bitPattern: bits)) / 32768
                squares += value * value
            }
            #expect(abs(sqrt(squares / 2400) - AACFixtureReference.initialRMS) < 0.01,
                    "Audio must begin immediately after the intentional source offset")
        }
        for cancellation in [false, true] {
            let directory = root.appendingPathComponent(cancellation ? "cancel" : "limit")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            do {
                _ = try Media3AudioCacheProbe.prepare(source: source.absoluteString, directory: directory.path,
                    maximumBytes: cancellation ? 64 * 1024 * 1024 : 128, cancelAfterCheck: cancellation ? 8 : 0)
                Issue.record("Expected audio preparation to stop")
            } catch {
                #expect(String(describing: error).contains(cancellation ? "cancelled" : "cache size limit"))
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        }
        #expect(try Data(contentsOf: source) == original)
    }

    @Test func pcmPacketCutsPreserveFramesOffsetsAndEndMarkers() {
        #expect(PcmBoundaryProbe.segments(cuts: [200_000, 250_500, 300_000], compressed: false)
                == [200_000, 204, 204, 0, 251_000, 196, 8, 1])
        #expect(PcmBoundaryProbe.segments(cuts: [200_000, 300_000], compressed: false)
                == [200_000, 400, 8, 1])
        #expect(PcmBoundaryProbe.segments(cuts: [299_500], compressed: false)
                == [200_000, 400, 8, 1])
        // Compressed access units cannot be split at PCM frame boundaries.
        #expect(PcmBoundaryProbe.segments(cuts: [250_500], compressed: true)
                == [200_000, 400, 8, 1])
    }

    @Test(arguments: [Int64(0), 250_000, 250_001, 300_000], ["music.wav", "music.m4a", "red-with-music.mp4", "red-with-offset-music.mp4"])
    func previewAudioTrimKeepsFadeTiming(sourceStartMicroseconds: Int64, fixture: String) async throws {
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let audio = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: fixture))
        defer { for url in [image, audio] { try? FileManager.default.removeItem(at: url) } }
        let sourceOffset: Int64 = fixture == "red-with-offset-music.mp4" ? 250_000 : 0
        func time(_ milliseconds: Int64) throws -> VideoTime { try VideoTime(value: milliseconds, timescale: 1000) }
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [
            MediaTrack(clips: [MediaClip(source: .image(image), duration: try time(2500))]),
            MediaTrack(clips: [MediaClip(source: fixture.hasSuffix("mp4") ? .video(audio) : .audio(audio), start: try time(500),
                duration: try time(1500), sourceStart: try VideoTime(value: sourceOffset + sourceStartMicroseconds, timescale: 1_000_000),
                audio: AudioSettings(volume: 0.5, fadeIn: try time(250), fadeOut: try time(250)))])
        ])
        try project.validate()
        let plan = try AndroidRenderPlan(project: project, settings: ExportSettings(resolution: project.canvas))
        let json = try #require(String(data: JSONEncoder().encode(plan), encoding: .utf8))
        let probe = Media3PreviewProbe()
        defer { probe.release() }
        try probe.start(json: json, sample: AndroidRenderPlan.visualSampler(for: project))
        probe.play()
        let deadline = ContinuousClock.now.advanced(by: .seconds(8))
        while probe.positionMilliseconds() < 2050 && ContinuousClock.now < deadline {
            try #require(probe.status() >= 0, "Audio preview failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        probe.pause()
        try #require(probe.positionMilliseconds() >= 2050)
        let sound = probe.audioRMS()
        let source = try Media3TestSupport.audioRMS(path: audio.path)
        try #require(sound.count == 3 && sound.allSatisfy { $0 >= 0 })
        let peak = source[1] * 0.5
        // RMS of a linear ramp from a to b is sqrt((a*a + a*b + b*b) / 3).
        // Probe windows cover clip-relative 0...50 ms and 1437.5...1487.5 ms.
        let expected = [peak * sqrt(0.04 / 3), peak, peak * sqrt(0.0775 / 3)]
        for index in 0..<3 {
            #expect(abs(sound[index] - expected[index]) < 0.01,
                    "\(fixture) trim \(sourceStartMicroseconds) us, PCM window \(index): expected \(expected), received \(sound)")
        }
        let frames = probe.frameCount()
        probe.seek(milliseconds: 1731)
        let seekDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (probe.frameCount() <= frames || probe.positionMilliseconds() >= 1900) && ContinuousClock.now < seekDeadline {
            try #require(probe.status() >= 0, "Seek failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(probe.frameCount() > frames && probe.positionMilliseconds() < 1900)
        probe.play()
        let resumeDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.positionMilliseconds() < 2050 && ContinuousClock.now < resumeDeadline {
            try #require(probe.status() >= 0, "Resume failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        probe.pause()
        try #require(probe.positionMilliseconds() >= 2050)
        let resumed = probe.audioRMS()
        try #require(resumed.count == 3 && resumed[2] >= 0)
        #expect(abs(resumed[2] - expected[2]) < 0.01,
                "\(fixture) trim \(sourceStartMicroseconds) us after seek: expected \(expected[2]), received \(resumed[2])")
    }

    @Test func canonicalCompositionPreviewMatchesExportedLayersAndAnimation() async throws {
        let image = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        let video = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "red.mp4"))
        let audio = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let output = image.deletingLastPathComponent().appendingPathComponent("preview-reference-\(UUID()).mp4")
        defer { for url in [image, video, audio, output] { try? FileManager.default.removeItem(at: url) } }
        func time(_ milliseconds: Int64) throws -> VideoTime { try VideoTime(value: milliseconds, timescale: 1000) }
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180),
            background: VideoColor(red: 0, green: 0, blue: 1), tracks: [
                MediaTrack(clips: [MediaClip(source: .image(image), duration: try time(3000), zIndex: 1,
                    transform: VisualTransform(width: 0.2, height: 0.2, contentMode: .stretch), animations: [
                        KeyframeAnimation(property: .x, keyframes: [Keyframe(time: .zero, value: 0.25),
                                                                  Keyframe(time: try time(3000), value: 0.75)])
                    ])]),
                MediaTrack(clips: [MediaClip(source: .text("PREVIEW", TextStyle(fontSize: 24)),
                    start: try time(1000), duration: try time(1500), zIndex: 2,
                    transform: VisualTransform(y: 0.2, width: 0.8, height: 0.25))]),
                MediaTrack(clips: [MediaClip(source: .video(video), start: try time(4000),
                    duration: try time(500), sourceStart: try time(250))]),
                MediaTrack(clips: [MediaClip(source: .audio(audio), start: try time(500),
                    duration: try time(1500), sourceStart: try time(250),
                    audio: AudioSettings(volume: 0.5, fadeIn: try time(250), fadeOut: try time(250)))])
            ])
        try project.validate()
        let settings = ExportSettings(resolution: project.canvas, frameRate: .fps30, videoBitRate: 2_000_000)
        try await VideoExporter().export(project, to: output, settings: settings)
        let exportColors = try Media3TestSupport.videoColorInfo(path: output.path)
        let plan = try AndroidRenderPlan(project: project, settings: settings)
        let json = try #require(String(data: JSONEncoder().encode(plan), encoding: .utf8))
        let probe = Media3PreviewProbe()
        defer { probe.release() }
        try probe.start(json: json, sample: AndroidRenderPlan.visualSampler(for: project))

        for milliseconds: Int64 in [500, 1500, 2500, 3500, 4250, 1500] {
            let previousCount = probe.frameCount()
            probe.seek(milliseconds: milliseconds)
            let deadline = ContinuousClock.now.advanced(by: .seconds(10))
            var matched = false
            while ContinuousClock.now < deadline {
                try #require(probe.status() >= 0, "Canonical preview: \(probe.failureMessage())")
                let stats = probe.spatialStats()
                let pixels = probe.pixels()
                if probe.frameCount() > previousCount, stats.count == 4, pixels.count == 6 {
                    let hasGreen = milliseconds < 3000
                    let hasText = milliseconds >= 1000 && milliseconds < 2500
                    let isRed = milliseconds >= 4000
                    let expectedX = (0.25 + Double(milliseconds) / 3000 * 0.5) * 320
                    let correctGreen = hasGreen ? (stats[0] > 1500 && abs(Double(stats[1]) / 1000 - expectedX) < 3) : stats[0] == 0
                    let correctText = hasText ? stats[2] > 40 : stats[2] == 0
                    let correctBackground = isRed ? (pixels[3] > 210 && pixels[5] < 40) : (pixels[3] < 40 && pixels[5] > 210)
                    if correctGreen && correctText && correctBackground { matched = true; break }
                }
                try await Task.sleep(for: .milliseconds(25))
            }
            try #require(matched, "Wrong canonical preview at \(milliseconds) ms: pixels \(probe.pixels()), spatial stats \(probe.spatialStats()), frames \(probe.frameCount())")
            let rendered = try Media3TestSupport.frameStats(path: output.path, timeUs: milliseconds * 1000)
            let preview = probe.pixels()
            for channel in 0..<3 {
                #expect(abs(rendered[3 + channel] - Double(preview[channel])) <= 8,
                        "Preview/export center channel \(channel) at \(milliseconds) ms: export \(Array(rendered[3...5])), preview \(Array(preview[0..<3])), tags \(exportColors)")
            }
            if milliseconds == 1500 {
                #expect(abs(rendered[9] - Double(probe.spatialStats()[3]) / 1000) < 3,
                        "Preview and export must position the same rasterized text")
            }
        }
        let beforeScrub = probe.frameCount()
        for target: Int64 in [2500, 500, 3500, 1000, 1500] { probe.seek(milliseconds: target) }
        probe.replaceSurface()
        let scrubDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        var scrubMatched = false
        while ContinuousClock.now < scrubDeadline {
            let stats = probe.spatialStats()
            if probe.frameCount() > beforeScrub, abs(probe.positionMilliseconds() - 1500) < 25,
               stats.count == 4, stats[0] > 1500, abs(Double(stats[1]) / 1000 - 160) < 3, stats[2] > 40 {
                scrubMatched = true
                break
            }
            try #require(probe.status() >= 0, "Rapid seek failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(scrubMatched, "Rapid scrubbing must display the final requested frame")
        probe.seek(milliseconds: 0)
        let playbackFrames = probe.frameCount()
        probe.play()
        let playbackDeadline = ContinuousClock.now.advanced(by: .seconds(8))
        while probe.positionMilliseconds() < 2050 && ContinuousClock.now < playbackDeadline {
            try #require(probe.status() >= 0, "Playback failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        probe.pause()
        #expect(probe.positionMilliseconds() >= 2050, "Playback must advance the composition clock")
        #expect(probe.frameCount() > playbackFrames + 10, "Playback must deliver changing surface frames")
        let sound = probe.audioRMS()
        let original = try Media3TestSupport.audioRMS(path: audio.path)
        try #require(sound.count == 3 && sound.allSatisfy { $0 >= 0 }, "Missing live PCM windows: \(sound)")
        #expect(abs(sound[1] - original[1] * 0.5) < 0.01, "Live playback must apply clip volume: \(sound)")
        #expect(sound[0] < sound[1] * 0.3 && sound[2] < sound[1] * 0.3,
                "Live playback must preserve both fades: \(sound)")
        let previousFrames = probe.frameCount()
        probe.seek(milliseconds: 1500)
        let seekDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (probe.frameCount() <= previousFrames || probe.positionMilliseconds() >= 1600)
                && ContinuousClock.now < seekDeadline {
            try #require(probe.status() >= 0, "Seek failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        try #require(probe.frameCount() > previousFrames && probe.positionMilliseconds() < 1600)
        probe.play()
        let resumedDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.positionMilliseconds() < 2050 && ContinuousClock.now < resumedDeadline {
            try #require(probe.status() >= 0, "Resumed playback failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(25))
        }
        probe.pause()
        let pausedDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while probe.isPlaying() && ContinuousClock.now < pausedDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(!probe.isPlaying())
        let resumed = probe.audioRMS()
        #expect(probe.positionMilliseconds() >= 2050)
        try #require(resumed.count == 3 && resumed[2] >= 0, "Missing resumed PCM: \(resumed)")
        #expect(resumed[2] < sound[1] * 0.3, "Seeking must preserve the fade-out clock: \(resumed)")
        let beforeReplacement = probe.frameCount()
        let positionBeforeReplacement = probe.positionMilliseconds()
        probe.play()
        let playingDeadline = ContinuousClock.now.advanced(by: .seconds(1))
        while !probe.isPlaying() && ContinuousClock.now < playingDeadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        try #require(probe.isPlaying())
        probe.replaceSurface()
        let replacementDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (probe.frameCount() <= beforeReplacement || probe.positionMilliseconds() <= positionBeforeReplacement + 100)
                && ContinuousClock.now < replacementDeadline {
            try #require(probe.status() >= 0, "Surface replacement failed: \(probe.failureMessage())")
            #expect(probe.isPlaying(), "Surface replacement must not report a user pause")
            try await Task.sleep(for: .milliseconds(20))
        }
        probe.pause()
        #expect(probe.frameCount() > beforeReplacement)
        #expect(probe.positionMilliseconds() > positionBeforeReplacement + 100,
                "Replacing the output surface must preserve the playing clock")
        probe.play()
        let endDeadline = ContinuousClock.now.advanced(by: .seconds(7))
        while (probe.positionMilliseconds() < 4490 || probe.isPlaying()) && ContinuousClock.now < endDeadline {
            try #require(probe.status() >= 0, "Playback completion failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(20))
        }
        try #require(probe.positionMilliseconds() >= 4490 && !probe.isPlaying(),
            "End state: position \(probe.positionMilliseconds()), playing \(probe.isPlaying()), pixels \(probe.pixels()), frames \(probe.frameCount())")
        let finalPixels = probe.pixels()
        #expect(finalPixels.count == 6 && finalPixels[0] > 210 && finalPixels[2] < 40,
                "Playback must render the final video segment: \(finalPixels)")
        let beforeReplay = probe.frameCount()
        probe.replaceSurface()
        probe.play()
        let replayDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while (probe.frameCount() <= beforeReplay || probe.positionMilliseconds() >= 1000 || !probe.isPlaying())
                && ContinuousClock.now < replayDeadline {
            try #require(probe.status() >= 0, "Replay failed: \(probe.failureMessage())")
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.frameCount() > beforeReplay && probe.positionMilliseconds() < 1000 && probe.isPlaying(),
                "Playback at the end must restart after replacing its surface")
        probe.release()
        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.status() != 3 && ContinuousClock.now < deadline { try await Task.sleep(for: .milliseconds(20)) }
        #expect(probe.status() == 3)
    }

    @Test(arguments: ["seek", "reset", "recreate"])
    func compositionPlayerDisplaysLayersAndSeeksAcrossGaps(seekMode: String) async throws {
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "green.png"))
        defer { try? FileManager.default.removeItem(at: source) }
        let probe = Media3PreviewProbe()
        defer { probe.release() }
        try probe.start(imagePath: source.path, seekMode: seekMode)

        func waitForFrame(after count: Int, green: Bool) async throws {
            let deadline = ContinuousClock.now.advanced(by: .seconds(20))
            while ContinuousClock.now < deadline {
                try #require(probe.status() >= 0, "CompositionPlayer: \(probe.failureMessage())")
                let pixels = probe.pixels()
                if probe.frameCount() > count, pixels.count == 6,
                   pixels[0] < 40, pixels[3] < 40, pixels[4] < 40, pixels[5] > 210,
                   green ? (pixels[1] > 210 && pixels[2] < 40) : (pixels[1] < 40 && pixels[2] > 210) {
                    return
                }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(Bool(false), "Missing \(green ? "green overlay" : "blue background") frame: \(probe.pixels()); frames \(probe.frameCount()); error \(probe.failureMessage()); seekMode=\(seekMode)")
        }

        try await waitForFrame(after: 0, green: false)
        print("CompositionPlayer first decoded surface frame: \(probe.firstFrameMilliseconds()) ms for an 18-second composition")
        let firstCount = probe.frameCount()
        probe.seek(milliseconds: 6_000)
        try await waitForFrame(after: firstCount, green: true)
        let overlayCount = probe.frameCount()
        probe.seek(milliseconds: 12_000)
        try await waitForFrame(after: overlayCount, green: false)
        let gapCount = probe.frameCount()
        probe.seek(milliseconds: 6_000)
        try await waitForFrame(after: gapCount, green: true)
        probe.release()
        let releaseDeadline = ContinuousClock.now.advanced(by: .seconds(5))
        while probe.status() != 3 && ContinuousClock.now < releaseDeadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(probe.status() == 3)
    }
}
#endif
