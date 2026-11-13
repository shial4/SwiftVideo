// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct AudioEffectTests {
    private func clip(_ filters: [AudioFilter]) throws -> MediaClip {
        MediaClip.audio(URL(fileURLWithPath: "/unused.wav"), duration: try VideoTime(value: 1, timescale: 1))
            .audio(AudioSettings(filters: filters))
    }

    @Test func audioReferencesRoundTripAndUseTheSharedValidationContract() throws {
        let definition = CustomAudioFixture.definition()
        let registry = try EffectRegistry(audio: [definition])
        let project = VideoProject(tracks: [MediaTrack(clips: [try clip([.custom(EffectReference(definition.id))])])])
        let decoded = try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project))
        #expect(decoded == project)
        for platform in EffectPlatform.allCases { try registry.validate(decoded, for: platform) }
        #expect(registry.supportedPlatforms(for: definition.id) == Set(EffectPlatform.allCases))
        #expect(throws: VideoError.self) { try EffectRegistry.empty.validate(decoded, for: .apple) }
        #expect(throws: VideoError.self) { try EffectRegistry(audio: [definition, definition]) }
        #expect(throws: VideoError.self) { try EffectRegistry(visual: [VisualEffectDefinition(definition.id)], audio: [definition]) }
        let appleOnly = AudioEffectDefinition(definition.id, platforms: [.apple], makeProcessor: definition.factory)
        #expect(throws: VideoError.self) { try EffectRegistry(audio: [appleOnly]).validate(decoded, for: .android) }
        #expect(throws: VideoError.self) { try registry.resolveAudio(EffectReference(definition.id, parameters: ["gain": .number(5)]), for: .apple) }
        #expect(throws: VideoError.self) { try registry.resolveAudio(EffectReference(definition.id, parameters: ["unknown": .boolean(true)]), for: .android) }
        #expect(throws: VideoError.self) { try registry.resolveAudio(EffectReference(EffectIdentifier(definition.id.name, version: 2)), for: .apple) }
        let capabilities = RendererCapabilities(name: "Limited", features: Set(CompositionFeature.allCases).subtracting([.customAudioEffects]), codecs: [.h264], containers: [.mp4])
        #expect(throws: VideoError.self) { try capabilities.validate(decoded, settings: ExportSettings()) }
    }

    @Test func delayPreservesChannelsAcrossBuffersAndResetClearsHistory() throws {
        let counts = AudioEffectCounts()
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(mode: .delay, counts: counts)])
        var chain = try AudioEffectChain(clip: clip([.custom(EffectReference(CustomAudioFixture.id))]), registry: registry,
            platform: .apple, format: AudioEffectFormat(sampleRate: 48_000, channels: 2))
        var first: [Float] = [1, 2, 3, 4], second: [Float] = [5, 6]
        try chain.process(&first); try chain.process(&second)
        #expect(first == [0, 0, 1, 2] && second == [3, 4])
        chain.reset()
        var afterSeek: [Float] = [7, 8]
        try chain.process(&afterSeek)
        #expect(afterSeek == [0, 0])
        chain.finish(); chain.finish()
        let result = counts.state.withLock { $0 }
        #expect(result.created == 1 && result.resets == 2 && result.finished == 1)
        #expect(result.contexts.map(\.projectTime) == [0, 2.0 / 48_000, 0])
    }

    @Test func freshClipsHaveIndependentDSPAndRetimedSourceClocks() throws {
        let counts = AudioEffectCounts()
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(mode: .delay, counts: counts)])
        let clip = try MediaClip(source: .audio(URL(fileURLWithPath: "/unused.wav")), start: VideoTime(value: 2, timescale: 1),
            duration: VideoTime(value: 1, timescale: 1), sourceStart: VideoTime(value: 1, timescale: 4),
            audio: AudioSettings(filters: [.custom(EffectReference(CustomAudioFixture.id))])).speed(.double)
        let format = try AudioEffectFormat(sampleRate: 48_000, channels: 1)
        var first = try AudioEffectChain(clip: clip, registry: registry, platform: .android, format: format)
        var second = try AudioEffectChain(clip: clip, registry: registry, platform: .android, format: format)
        defer { first.finish(); second.finish() }
        var impulse: [Float] = [1], zeros: [Float] = [0]
        try first.process(&impulse); try first.process(&zeros)
        #expect(zeros == [1])
        try second.process(&zeros)
        #expect(zeros == [0])
        let contexts = counts.state.withLock { $0.contexts }
        #expect(contexts[0].projectTime == 2 && contexts[0].sourceTime == 0.25 && contexts[0].effectTime == 0)
        #expect(abs(contexts[1].sourceTime - (0.25 + 2.0 / 48_000)) < 1e-10)
        #expect(contexts[2].projectTime == 2)
    }

    @Test func mixedEQAndCustomStagesPreserveAuthoredOrder() throws {
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(mode: .offset)])
        let custom = AudioFilter.custom(EffectReference(CustomAudioFixture.id))
        let highPass = AudioFilter.highPass(cutoffHz: 200)
        func last(_ filters: [AudioFilter]) throws -> Float {
            var chain = try AudioEffectChain(clip: clip(filters), registry: registry, platform: .apple,
                format: AudioEffectFormat(sampleRate: 48_000, channels: 1))
            defer { chain.finish() }
            var samples = [Float](repeating: 0, count: 4800)
            try chain.process(&samples)
            return try #require(samples.last)
        }
        #expect(abs(try last([custom, highPass])) < 0.001)
        #expect(abs(try last([highPass, custom]) - 0.25) < 0.001)
    }

    @Test(arguments: [CustomAudioFixture.Mode.fail, .resize, .nonfinite])
    func invalidProcessorOutputFailsAndCanBeCleanedUp(mode: CustomAudioFixture.Mode) throws {
        let counts = AudioEffectCounts()
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(mode: mode, counts: counts)])
        var chain = try AudioEffectChain(clip: clip([.custom(EffectReference(CustomAudioFixture.id))]), registry: registry,
            platform: .apple, format: AudioEffectFormat(sampleRate: 48_000, channels: 2))
        var samples: [Float] = [0, 0]
        #expect(throws: VideoError.self) { try chain.process(&samples) }
        chain.finish()
        #expect(counts.state.withLock { $0.finished } == 1)
    }

    @Test(arguments: [AudioFilter.lowPass(cutoffHz: 100), .highPass(cutoffHz: 2_000),
        .parametricEQ(frequencyHz: 440, gainDB: -12, bandwidthOctaves: 1),
        .parametricEQ(frequencyHz: 23_999, gainDB: -12, bandwidthOctaves: 5)])
    func mixedChainEQAttenuatesTheExpectedTone(filter: AudioFilter) throws {
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition()])
        var chain = try AudioEffectChain(clip: clip([.custom(EffectReference(CustomAudioFixture.id, parameters: ["gain": .number(1)])), filter]),
            registry: registry, platform: .android, format: AudioEffectFormat(sampleRate: 48_000, channels: 1))
        defer { chain.finish() }
        var samples = (0..<4800).map { Float(sin(Double($0) * 2 * .pi * 440 / 48_000)) }
        try chain.process(&samples)
        let values = samples.suffix(2400)
        let rms = sqrt(values.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(values.count))
        #expect(rms.isFinite && rms < 0.25)
    }

    @Test func laterFactoryFailureReleasesEarlierStagesAndInvalidFormatsFail() throws {
        let counts = AudioEffectCounts(), bad = EffectIdentifier("test.bad-audio")
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(counts: counts),
            AudioEffectDefinition(bad) { _, _ in throw VideoError.renderingFailed("Preparation failed") }])
        #expect(throws: VideoError.self) {
            try AudioEffectChain(clip: clip([.custom(EffectReference(CustomAudioFixture.id)), .custom(EffectReference(bad))]),
                registry: registry, platform: .apple, format: AudioEffectFormat(sampleRate: 48_000, channels: 2))
        }
        #expect(counts.state.withLock { $0.finished } == 1)
        #expect(throws: VideoError.self) { try AudioEffectFormat(sampleRate: 0, channels: 2) }
        #expect(throws: VideoError.self) { try AudioEffectFormat(sampleRate: 48_000, channels: 6) }
        var chain = try AudioEffectChain(clip: clip([]), registry: .empty, platform: .apple,
            format: AudioEffectFormat(sampleRate: 48_000, channels: 2))
        var incomplete: [Float] = [0]
        #expect(throws: VideoError.self) { try chain.process(&incomplete) }
    }

    #if os(Android)
    @Test func androidBufferBoundaryHandlesResetFormatChangesAndFinish() throws {
        let counts = AudioEffectCounts()
        let registry = try EffectRegistry(audio: [CustomAudioFixture.definition(mode: .delay, counts: counts)])
        let session = try AndroidAudioEffects(clip: clip([.custom(EffectReference(CustomAudioFixture.id))]), registry: registry)
        func data(_ samples: [Float]) -> Data { samples.withUnsafeBytes { Data($0) } }
        func samples(_ data: Data) -> [Float] {
            var values = [Float](repeating: 0, count: data.count / 4)
            _ = values.withUnsafeMutableBytes { data.copyBytes(to: $0) }
            return values
        }
        _ = try session.process(Data(), sampleRate: 48_000, channels: 2, reset: true)
        #expect(try samples(session.process(data([1, 2, 3, 4]), sampleRate: 48_000, channels: 2, reset: false)) == [0, 0, 1, 2])
        _ = try session.process(Data(), sampleRate: 48_000, channels: 2, reset: true)
        #expect(try samples(session.process(data([5, 6]), sampleRate: 48_000, channels: 2, reset: false)) == [0, 0])
        #expect(try samples(session.process(data([7]), sampleRate: 44_100, channels: 1, reset: false)) == [0])
        #expect(throws: VideoError.self) { try session.process(Data([0]), sampleRate: 44_100, channels: 1, reset: false) }
        session.finish(); session.finish()
        #expect(throws: VideoError.self) { try session.process(Data(), sampleRate: 44_100, channels: 1, reset: true) }
        let result = counts.state.withLock { $0 }
        #expect(result.created == 2 && result.resets == 3 && result.finished == 2)
    }
    #endif
}
