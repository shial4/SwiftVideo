// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreImage) && !SWIFTVIDEO_CORE_COVERAGE
import CoreImage
import Foundation
import os
import Testing
@testable import SwiftVideo

@Suite struct AppleEffectLifecycleTests {
    @Test func preparationCreatesIndependentInstancesAndReleasesThemExactlyOnce() throws {
        let counts = LifecycleCounts()
        let id = EffectIdentifier("test.lifecycle")
        let definition = VisualEffectDefinition(id).apple { _ in
            counts.state.withLock { $0.created += 1 }
            return LifecycleProcessor(counts: counts)
        }
        let registry = try EffectRegistry(visual: [definition])
        let first = MediaClip.text("First", duration: try VideoTime(value: 1, timescale: 1)).filter(.custom(EffectReference(id)))
        let second = MediaClip.text("Second", duration: first.duration).filter(.custom(EffectReference(id)))
        let effects = try AppleVisualEffects(clips: [first, second], registry: registry)
        let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        _ = try effects.apply(to: input, clipID: first.id, filterIndex: 0, projectTime: 0)
        _ = try effects.apply(to: input, clipID: first.id, filterIndex: 0, projectTime: 0.5)
        _ = try effects.apply(to: input, clipID: second.id, filterIndex: 0, projectTime: 0)
        effects.finish()
        effects.finish()
        let result = counts.state.withLock { $0 }
        #expect(result.created == 2 && result.applied == 3 && result.finished == 2)
        #expect(throws: VideoError.self) { try effects.apply(to: input, clipID: first.id, filterIndex: 0, projectTime: 0) }
    }

    @Test func laterFactoryFailureReleasesAlreadyPreparedProcessors() throws {
        let counts = LifecycleCounts()
        let good = EffectIdentifier("test.good")
        let bad = EffectIdentifier("test.bad")
        let registry = try EffectRegistry(visual: [
            VisualEffectDefinition(good).apple { _ in LifecycleProcessor(counts: counts) },
            VisualEffectDefinition(bad).apple { _ in throw VideoError.renderingFailed("Preparation failed") }
        ])
        let clip = MediaClip.text("Title", duration: try VideoTime(value: 1, timescale: 1))
            .filter(.custom(EffectReference(good))).filter(.custom(EffectReference(bad)))
        #expect(throws: VideoError.renderingFailed("Preparation failed")) {
            try AppleVisualEffects(clips: [clip], registry: registry)
        }
        #expect(counts.state.withLock { $0.finished } == 1)
    }

    @Test func invalidOutputExtentFailsAndMediaFailureReleasesProcessor() async throws {
        let counts = LifecycleCounts()
        let id = EffectIdentifier("test.extent")
        let registry = try EffectRegistry(visual: [VisualEffectDefinition(id).apple { _ in
            LifecycleProcessor(counts: counts, invalidExtent: true)
        }])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-lifecycle-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip.image(folder.appendingPathComponent("missing.png"), duration: try VideoTime(value: 1, timescale: 1))
            .filter(.custom(EffectReference(id)))
        let effects = try AppleVisualEffects(clips: [clip], registry: registry)
        let input = CIImage(color: .red).cropped(to: CGRect(x: 0, y: 0, width: 16, height: 16))
        #expect(throws: VideoError.self) { try effects.apply(to: input, clipID: clip.id, filterIndex: 0, projectTime: 0) }
        effects.finish()
        await #expect(throws: VideoError.self) {
            try await VideoExporter(effects: registry).export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: folder.appendingPathComponent("output.mp4"))
        }
        #expect(counts.state.withLock { $0.finished } == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @Test func cancellationDuringCustomRenderingReleasesTheProcessor() async throws {
        let counts = LifecycleCounts()
        let id = EffectIdentifier("test.cancel")
        let registry = try EffectRegistry(visual: [VisualEffectDefinition(id).apple { _ in
            LifecycleProcessor(counts: counts, cancelOnApply: true)
        }])
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("custom-cancel-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let image = try #require(Bundle.module.url(forResource: "green", withExtension: "png"))
        let clip = MediaClip.image(image, duration: try VideoTime(value: 1, timescale: 1)).filter(.custom(EffectReference(id)))
        await #expect(throws: VideoError.cancelled) {
            try await VideoExporter(effects: registry).export(VideoProject(tracks: [MediaTrack(clips: [clip])]),
                to: folder.appendingPathComponent("cancelled.mp4"), settings: ExportSettings(resolution: VideoSize(width: 320, height: 180)))
        }
        let result = counts.state.withLock { $0 }
        #expect(result.applied == 1 && result.finished == 1)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
}

private final class LifecycleCounts: Sendable {
    let state = OSAllocatedUnfairLock(initialState: (created: 0, applied: 0, finished: 0))
}

private final class LifecycleProcessor: AppleVisualEffectProcessor {
    private let counts: LifecycleCounts
    private let invalidExtent: Bool
    private let cancelOnApply: Bool
    init(counts: LifecycleCounts, invalidExtent: Bool = false, cancelOnApply: Bool = false) {
        self.counts = counts
        self.invalidExtent = invalidExtent
        self.cancelOnApply = cancelOnApply
    }
    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
        counts.state.withLock { $0.applied += 1 }
        if cancelOnApply { withUnsafeCurrentTask { $0?.cancel() } }
        return invalidExtent ? CIImage(color: .red) : image
    }
    func finish() { counts.state.withLock { $0.finished += 1 } }
}
#endif
