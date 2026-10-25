// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if os(Android)
import Foundation
import SwiftVideoMedia3

/// Media3 owns native Android codecs. The bridge is authored entirely in Swift.
public actor AndroidVideoRenderer: VideoRendering {
    public nonisolated let capabilities = RendererCapabilities(name: "Media3 Transformer",
        features: Set(CompositionFeature.allCases), codecs: [.h264, .hevc], containers: [.mp4])

    public init() {}

    public func render(_ project: VideoProject, to destination: URL, settings: ExportSettings,
                       progress: @escaping @Sendable (ExportProgress) -> Void) async throws {
        try project.validate()
        try settings.validate(for: project)
        try capabilities.validate(project, settings: settings)
        let rate = settings.frameRate ?? project.frameRate
        guard rate.denominator == 1 else {
            throw VideoError.unsupportedFeature("Media3 image-sequence frame timing currently requires an integer frame rate.")
        }
        let size = settings.resolution ?? project.canvas
        guard size.width <= 8192, size.height <= 8192, rate.framesPerSecond <= 240 else {
            throw VideoError.unsupportedFeature("This renderer supports output up to 8192 pixels per dimension and 240 fps.")
        }
        let plan = try AndroidRenderPlan(project: project, settings: settings)
        let encoded = try JSONEncoder().encode(plan)
        guard let json = String(data: encoded, encoding: .utf8) else { throw VideoError.invalidProject("Cannot serialize Android render plan.") }
        let clips = Dictionary(uniqueKeysWithValues: project.tracks.flatMap(\.clips).map { ($0.id.uuidString, $0) })
        let session = try Media3ExportSession()
        progress(ExportProgress(phase: .preparing, fraction: 0))
        try session.start(json: json, outputPath: destination.path) { id, microseconds in
            guard let clip = clips[id], let time = try? VideoTime(value: Int64(microseconds.rounded()), timescale: 1_000_000),
                  (try? clip.timeRange.contains(time)) == true,
                  let transform = try? clip.visualTransform(at: time) else { return [0.5, 0.5, 1, 0, 0] }
            return [transform.x, transform.y, transform.scale, transform.rotation, transform.opacity]
        }
        do {
            while true {
                try Task.checkCancellation()
                let status = try session.currentStatus()
                if status == 2 { break }
                if status < 0 { throw VideoError.renderingFailed(try session.failureMessage()) }
                progress(ExportProgress(phase: .rendering, fraction: 0.95 * (try session.currentProgress())))
                try await Task.sleep(for: .milliseconds(100))
            }
            progress(ExportProgress(phase: .finishing, fraction: 0.95))
        } catch {
            try session.cancel()
            // Cancellation is queued on Media3's application looper. Wait for release
            // before the facade removes staging files.
            // An unstructured task does not inherit cancellation. Its suspension
            // remains effective even when the export's caller has been cancelled.
            try await Task {
                while try session.currentStatus() >= 0 && session.currentStatus() < 2 {
                    try await Task.sleep(for: .milliseconds(10))
                }
            }.value
            throw error
        }
    }
}

extension VideoExporter {
    public init() { self.init(renderer: AndroidVideoRenderer()) }
}
#endif
