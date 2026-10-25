// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct ExporterTests {
    @Test func encoderSettingsRejectUnrepresentableBitrates() throws {
        let snapshot = try project()
        #expect(throws: VideoError.self) { try ExportSettings(videoBitRate: Int.max).validate(for: snapshot) }
        #expect(throws: VideoError.self) { try ExportSettings(audioBitRate: Int.max).validate(for: snapshot) }
        #expect(throws: VideoError.self) {
            try ExportSettings(resolution: VideoSize(width: Int.max - 1, height: 1080)).effectiveVideoBitRate(for: snapshot)
        }
        #expect(try FrameRate(numerator: 60, denominator: 2) == .fps30)
    }

    @Test func failureRemovesStagingFile() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = VideoExporter(renderer: ExportRendererStub(mode: .fail))
        await #expect(throws: VideoError.renderingFailed("Injected renderer failure.")) {
            try await exporter.export(project(), to: directory.appendingPathComponent("output.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    @Test func existingOutputIsPreserved() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("existing.mp4")
        let original = Data("original".utf8)
        try original.write(to: destination)
        await #expect(throws: VideoError.destinationExists) {
            try await VideoExporter(renderer: ExportRendererStub(mode: .fail)).export(project(), to: destination)
        }
        #expect(try Data(contentsOf: destination) == original)
    }

    @Test func explicitCancellationReleasesExporterAndStagingFile() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let exporter = VideoExporter(renderer: ExportRendererStub(mode: .wait))
        let snapshot = try project()
        let destination = directory.appendingPathComponent("output.mp4")
        let (events, continuation) = AsyncStream<ExportProgress>.makeStream()
        let task = Task { try await exporter.export(snapshot, to: destination) { continuation.yield($0) } }
        var iterator = events.makeAsyncIterator()
        _ = await iterator.next()
        await #expect(throws: VideoError.exportInProgress) { try await exporter.export(snapshot, to: destination) }
        await exporter.cancel()
        await #expect(throws: VideoError.cancelled) { try await task.value }
        continuation.finish()
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
        // A new request is accepted after cancellation; it reaches the stub again.
        let (secondEvents, secondContinuation) = AsyncStream<ExportProgress>.makeStream()
        let second = Task { try await exporter.export(snapshot, to: destination) { secondContinuation.yield($0) } }
        var secondIterator = secondEvents.makeAsyncIterator()
        _ = await secondIterator.next()
        second.cancel()
        await #expect(throws: VideoError.cancelled) { try await second.value }
        secondContinuation.finish()
    }

    @Test func unsupportedCapabilitiesFailBeforeRendering() async throws {
        let directory = try scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let limited = ExportRendererStub(mode: .fail, features: [])
        await #expect(throws: VideoError.self) {
            try await VideoExporter(renderer: limited).export(project(), to: directory.appendingPathComponent("output.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
    }

    private func project() throws -> VideoProject {
        VideoProject(tracks: [MediaTrack(clips: [MediaClip(source: .text("Test", TextStyle()),
                                                          duration: try VideoTime(value: 1, timescale: 1))])])
    }

    private func scratchDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("swiftvideo-exporter-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Deliberately writes invalid media: this stub tests export lifecycle, never media correctness.
private actor ExportRendererStub: VideoRendering {
    enum Mode: Sendable { case fail, wait }
    let mode: Mode
    nonisolated let capabilities: RendererCapabilities
    init(mode: Mode, features: Set<CompositionFeature> = [.text]) {
        self.mode = mode
        capabilities = RendererCapabilities(name: "Lifecycle test stub", features: features, codecs: [.h264], containers: [.mp4])
    }
    func render(_ project: VideoProject, to destination: URL, settings: ExportSettings,
                progress: @escaping @Sendable (ExportProgress) -> Void) async throws {
        try Data("partial output".utf8).write(to: destination)
        progress(ExportProgress(phase: .rendering, fraction: 0.1))
        switch mode {
        case .fail: throw VideoError.renderingFailed("Injected renderer failure.")
        case .wait: try await Task.sleep(for: .seconds(30))
        }
    }
}
