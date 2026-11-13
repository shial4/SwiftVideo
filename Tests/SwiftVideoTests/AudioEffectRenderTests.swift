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
#endif

@Suite(.serialized) struct AudioEffectRenderTests {
    @Test(arguments: [PlaybackRate.half, .double])
    func customGainAndEQRunAfterSpeedOnEncodedAudio(rate: PlaybackRate) async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let music = try music(in: folder)
        let clip = try MediaClip(source: .audio(music), duration: VideoTime(value: 4, timescale: 5),
            sourceStart: VideoTime(value: 1, timescale: 10)).speed(rate)
        let counts = AudioEffectCounts()
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(counts: counts)])
        let exporter = VideoExporter(effects: registry)
        let reference = EffectReference(CustomAudioFixture.id, parameters: ["gain": .number(0.25)])
        var levels: [Double] = []
        for custom in [false, true] {
            let filters: [AudioFilter] = custom ? [.highPass(cutoffHz: 40), .custom(reference), .lowPass(cutoffHz: 4_000)] : []
            let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [clip]).audioFilters(filters)])
            let destination = folder.appendingPathComponent(custom ? "wet.mp4" : "dry.mp4")
            try await exporter.export(project, to: destination)
            levels.append(try await level(destination, duration: clip.duration.seconds))
        }
        #expect(levels[0] > 0.05)
        #expect(abs(levels[1] / levels[0] - 0.25) < 0.06, "Encoded dry/wet RMS: \(levels)")
        let result = counts.state.withLock { $0 }
        #expect(result.created == 1 && result.resets >= 1 && result.finished == 1)
        let first = try #require(result.contexts.first), last = try #require(result.contexts.last)
        #expect(first.projectTime == 0 && first.effectTime == 0 && abs(first.sourceTime - 0.1) < 1e-9)
        #expect(last.projectTime > clip.duration.seconds * 0.7)
        #expect(abs(last.sourceTime - (0.1 + last.projectTime * rate.multiplier)) < 1e-9)
    }

    @Test(arguments: [CustomAudioFixture.Mode.prepareFail, .fail, .resize, .nonfinite])
    func failingAudioCleansUpAndExporterRemainsReusable(mode: CustomAudioFixture.Mode) async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.audio(try music(in: folder), duration: try VideoTime(value: 1, timescale: 2))
        let counts = AudioEffectCounts()
        let exporter = VideoExporter(effects: try EffectRegistry(audio: [CustomAudioFixture.definition(mode: mode, counts: counts)]))
        let destination = folder.appendingPathComponent("result.mp4")
        let settings = ExportSettings(resolution: VideoSize(width: 320, height: 180))
        let failed = VideoProject(tracks: [MediaTrack(clips: [clip]).audioFilter(.custom(EffectReference(CustomAudioFixture.id)))])
        await #expect(throws: VideoError.self) { try await exporter.export(failed, to: destination, settings: settings) }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { $0 == "music.wav" })
        let expected = mode == .prepareFail ? 0 : 1
        #expect(counts.state.withLock { $0.finished } == expected)
        try await exporter.export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: destination, settings: settings)
        #expect(FileManager.default.fileExists(atPath: destination.path))
    }

    @Test func unregisteredAudioFailsBeforeReadingMedia() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.audio(folder.appendingPathComponent("missing.wav"), duration: try VideoTime(value: 1, timescale: 1))
            .audio(AudioSettings(filters: [.custom(EffectReference(CustomAudioFixture.id))]))
        await #expect(throws: VideoError.unsupportedFeature("Audio effect 'test.audio' version 1 is not registered.")) {
            try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: folder.appendingPathComponent("result.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func cancellationReleasesCustomAudioAfterProcessingStarts() async throws {
        let folder = try folder()
        defer { try? FileManager.default.removeItem(at: folder) }
        let counts = AudioEffectCounts()
        let (events, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        defer { continuation.finish() }
        let definition = CustomAudioFixture.definition(counts: counts, onProcess: { continuation.yield(()) })
        let exporter = VideoExporter(effects: try EffectRegistry(audio: [definition]))
        let clip = try MediaClip.audio(music(in: folder), duration: VideoTime(value: 1, timescale: 1)).speed(.quarter)
            .audio(AudioSettings(filters: [.custom(EffectReference(CustomAudioFixture.id))]))
        let project = VideoProject(canvas: VideoSize(width: 320, height: 180), tracks: [MediaTrack(clips: [clip])])
        let operation = Task {
            defer { continuation.finish() }
            try await exporter.export(project, to: folder.appendingPathComponent("cancelled.mp4"))
        }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        operation.cancel()
        await #expect(throws: VideoError.cancelled) { try await operation.value }
        #expect(counts.state.withLock { $0.finished } == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { $0 == "music.wav" })
    }

    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("custom-audio-\(UUID())")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func music(in folder: URL) throws -> URL {
        #if os(Android)
        let source = URL(fileURLWithPath: try Media3TestSupport.copyFixture(name: "music.wav"))
        let destination = folder.appendingPathComponent("music.wav")
        try FileManager.default.moveItem(at: source, to: destination)
        return destination
        #else
        return try #require(Bundle.module.url(forResource: "music", withExtension: "wav"))
        #endif
    }

    private func level(_ url: URL, duration: Double) async throws -> Double {
        #if os(Android)
        return try Media3TestSupport.audioStats(path: url.path, duration: duration)[4]
        #else
        return try await AppleVideoRenderer().decodedAudioLevel(url, duration: duration)
        #endif
    }
}

#if !os(Android)
private extension AppleVideoRenderer {
    func decodedAudioLevel(_ url: URL, duration: Double) async throws -> Double {
        let asset = AVURLAsset(url: url)
        let track = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let clip = MediaClip.audio(url, duration: try VideoTime(value: Int64((duration * 48_000).rounded()), timescale: 48_000))
        let source = try AppleAudioSource(asset: asset, track: track, clip: clip)
        let start = Int64(duration * 48_000 / 4), end = Int64(duration * 48_000 * 3 / 4)
        var sum = 0.0
        for frame in start..<end { let value = Double(try source.sample(at: frame).0); sum += value * value }
        return sqrt(sum / Double(end - start))
    }
}
#endif
#endif
