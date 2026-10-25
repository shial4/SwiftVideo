// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum VideoCodec: String, Codable, Sendable, CaseIterable { case h264, hevc }
public enum VideoContainer: String, Codable, Sendable, CaseIterable { case mp4, mov }

public struct ExportSettings: Hashable, Codable, Sendable {
    public let resolution: VideoSize?
    public let frameRate: FrameRate?
    public let codec: VideoCodec
    public let container: VideoContainer
    public let quality: Double
    public let videoBitRate: Int?
    public let audioBitRate: Int

    public init(resolution: VideoSize? = nil, frameRate: FrameRate? = nil, codec: VideoCodec = .h264,
                container: VideoContainer = .mp4, quality: Double = 0.8, videoBitRate: Int? = nil,
                audioBitRate: Int = 192_000) {
        self.resolution = resolution; self.frameRate = frameRate; self.codec = codec
        self.container = container; self.quality = quality; self.videoBitRate = videoBitRate; self.audioBitRate = audioBitRate
    }

    public func validate(for project: VideoProject) throws {
        let size = resolution ?? project.canvas
        guard size.width > 0, size.height > 0, size.width.isMultiple(of: 2), size.height.isMultiple(of: 2) else {
            throw VideoError.invalidExport("Video encoding requires positive, even output dimensions.")
        }
        guard quality.isFinite, (0...1).contains(quality), videoBitRate.map({ (1...Int(Int32.max)).contains($0) }) ?? true,
              (1...Int(Int32.max)).contains(audioBitRate) else {
            throw VideoError.invalidExport("Quality must be between zero and one; bitrates must fit a positive 32-bit integer.")
        }
    }

    public func effectiveVideoBitRate(for project: VideoProject) throws -> Int {
        try validate(for: project)
        if let videoBitRate { return videoBitRate }
        let size = resolution ?? project.canvas
        let fps = (frameRate ?? project.frameRate).framesPerSecond
        let estimate = Double(size.width) * Double(size.height) * fps * (0.04 + quality * 0.16)
        guard estimate.isFinite, estimate <= Double(Int32.max) else { throw VideoError.invalidExport("Output dimensions exceed the encoder bitrate range.") }
        return max(128_000, Int(estimate))
    }
}

public enum CompositionFeature: String, Codable, Sendable, CaseIterable {
    case video, images, text, filters, animation, audioMixing, audioFades, audioPan, customFonts
}

public struct RendererCapabilities: Sendable {
    public let name: String
    public let features: Set<CompositionFeature>
    public let codecs: Set<VideoCodec>
    public let containers: Set<VideoContainer>
    public init(name: String, features: Set<CompositionFeature>, codecs: Set<VideoCodec>, containers: Set<VideoContainer>) {
        self.name = name; self.features = features; self.codecs = codecs; self.containers = containers
    }

    public func validate(_ project: VideoProject, settings: ExportSettings) throws {
        guard codecs.contains(settings.codec), containers.contains(settings.container) else {
            throw VideoError.unsupportedFeature("\(name) does not support the requested codec/container.")
        }
        for clip in project.tracks.flatMap(\.clips) {
            var required: Set<CompositionFeature> = []
            switch clip.source {
            case .video: required.insert(.video)
            case .image: required.insert(.images)
            case .audio: required.insert(.audioMixing)
            case .text(_, let style):
                required.insert(.text)
                if style.fontName != nil || style.fontURL != nil { required.insert(.customFonts) }
            }
            if !clip.filters.isEmpty { required.insert(.filters) }
            if !clip.animations.isEmpty { required.insert(.animation) }
            if clip.source.hasAudio && !clip.audio.isMuted {
                required.insert(.audioMixing)
                if clip.audio.fadeIn > .zero || clip.audio.fadeOut > .zero { required.insert(.audioFades) }
                if clip.audio.pan != 0 { required.insert(.audioPan) }
            }
            let missing = required.subtracting(features)
            guard missing.isEmpty else {
                throw VideoError.unsupportedFeature("\(name) does not support: \(missing.map(\.rawValue).sorted().joined(separator: ", ")).")
            }
        }
    }
}

public struct ExportProgress: Sendable, Equatable {
    public enum Phase: String, Sendable { case preparing, rendering, finishing, completed }
    public let phase: Phase
    public let fraction: Double
    public init(phase: Phase, fraction: Double) { self.phase = phase; self.fraction = min(1, max(0, fraction)) }
}

/// A renderer must finish a playable file or throw, poll cancellation, and release all media resources.
public protocol VideoRendering: Sendable {
    var capabilities: RendererCapabilities { get }
    func render(_ project: VideoProject, to destination: URL, settings: ExportSettings,
                progress: @escaping @Sendable (ExportProgress) -> Void) async throws
}

/// One export at a time. Output is staged beside the destination and published only after success.
public actor VideoExporter {
    private let renderer: any VideoRendering
    private var active: Task<Void, any Error>?

    public init(renderer: any VideoRendering) { self.renderer = renderer }
    public var capabilities: RendererCapabilities { renderer.capabilities }

    public func cancel() { active?.cancel() }

    @discardableResult
    public func export(_ project: VideoProject, to destination: URL, settings: ExportSettings = ExportSettings(),
                       progress: @escaping @Sendable (ExportProgress) -> Void = { _ in }) async throws -> URL {
        guard active == nil else { throw VideoError.exportInProgress }
        try project.validate()
        try settings.validate(for: project)
        try renderer.capabilities.validate(project, settings: settings)
        guard try project.duration > .zero else { throw VideoError.invalidProject("Cannot export an empty timeline.") }
        guard destination.isFileURL else { throw VideoError.invalidExport("Export requires a local file destination.") }
        let files = FileManager.default
        guard !files.fileExists(atPath: destination.path) else { throw VideoError.destinationExists }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".swiftvideo-\(UUID()).\(settings.container.rawValue)")
        let renderer = self.renderer
        // A retained task allows explicit cancellation as well as caller task cancellation.
        let task = Task { try await renderer.render(project, to: staging, settings: settings, progress: progress) }
        active = task
        defer {
            active = nil
            try? files.removeItem(at: staging)
        }
        do {
            try await withTaskCancellationHandler {
                try await task.value
                try Task.checkCancellation()
                guard !task.isCancelled else { throw CancellationError() }
            } onCancel: { task.cancel() }
            let attributes = try files.attributesOfItem(atPath: staging.path)
            guard let size = attributes[.size] as? NSNumber, size.int64Value > 0 else {
                throw VideoError.renderingFailed("The renderer produced no output.")
            }
            // FileManager move refuses to overwrite an output created concurrently.
            try files.moveItem(at: staging, to: destination)
            progress(ExportProgress(phase: .completed, fraction: 1))
            return destination
        } catch is CancellationError {
            throw VideoError.cancelled
        } catch let error as VideoError {
            throw error
        } catch {
            if task.isCancelled { throw VideoError.cancelled }
            throw VideoError.renderingFailed(error.localizedDescription)
        }
    }
}
