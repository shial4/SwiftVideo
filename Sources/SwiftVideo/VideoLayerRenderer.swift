// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import Metal
#elseif os(Android)
import SwiftVideoMedia3
#endif

/// Rasterizes a paused visual layer as a transparent PNG, without video encoding.
/// Crop, content sizing, text styling, and filters match the platform renderer.
/// The caller places the image using the clip's evaluated center, scale,
/// rotation, and opacity. These four properties are not baked into the image.
public actor VideoLayerRenderer {
    public init() {}

    /// `canvasSize` is the preview canvas resolution, before the clip's width and height.
    /// The destination must be a new local PNG. The caller owns the resulting file.
    public func render(clipID: UUID, in project: VideoProject, at time: VideoTime,
                       canvasSize: VideoSize? = nil, to destination: URL) async throws {
        try Task.checkCancellation()
        try project.validateForRendering()
        guard let clip = try project.renderClips().first(where: { $0.id == clipID }) else {
            throw VideoError.missingClip(clipID)
        }
        guard clip.source.isVisual, try clip.timeRange.contains(time) else {
            throw VideoError.invalidProject("The requested layer is not visible at this time.")
        }
        let size = canvasSize ?? project.canvas
        guard size.width > 0, size.height > 0, size.width <= 8192, size.height <= 8192 else {
            throw VideoError.invalidExport("Preview dimensions must be between 1 and 8192 pixels.")
        }
        let layerWidth = Double(size.width) * clip.transform.width
        let layerHeight = Double(size.height) * clip.transform.height
        guard layerWidth.isFinite, layerHeight.isFinite, layerWidth <= 8192, layerHeight <= 8192 else {
            throw VideoError.invalidExport("A preview layer supports up to 8192 pixels per dimension.")
        }
        guard destination.isFileURL, destination.pathExtension.lowercased() == "png" else {
            throw VideoError.invalidExport("A layer preview requires a local PNG destination.")
        }
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw VideoError.destinationExists }
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".layer-\(UUID()).png")
        defer { try? FileManager.default.removeItem(at: staging) }
        #if canImport(AVFoundation)
        try await renderApple(clip, project: project, time: time, size: size, to: staging)
        #elseif os(Android)
        let onlyLayer = VideoProject(canvas: project.canvas, frameRate: project.frameRate,
            background: .clear, tracks: [MediaTrack(clips: [clip])])
        let plan = try AndroidVideoRenderer.serializedPlan(onlyLayer, settings: ExportSettings(resolution: size, frameRate: .fps30))
        let seconds = try clip.sourceTime(at: time).seconds
        let session = Media3LayerSnapshotSession()
        try session.start(json: plan, sourceSeconds: seconds, outputPath: staging.path)
        do {
            while session.currentStatus() == 1 {
                try Task.checkCancellation()
                try await Task.sleep(for: .milliseconds(10))
            }
            guard session.currentStatus() == 2 else { throw VideoError.renderingFailed(session.failureMessage()) }
        } catch {
            session.cancel()
            // Wait for the worker to release GL resources before removing staging files.
            await Task {
                while session.currentStatus() == 1 { try? await Task.sleep(for: .milliseconds(10)) }
            }.value
            throw error
        }
        #else
        throw VideoError.unsupportedFeature("Layer previews require an Apple or Android renderer.")
        #endif
        try Task.checkCancellation()
        try FileManager.default.moveItem(at: staging, to: destination)
    }

    #if canImport(AVFoundation)
    private static let context: CIContext? = MTLCreateSystemDefaultDevice().map {
        CIContext(mtlDevice: $0, options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    }

    private func renderApple(_ clip: MediaClip, project: VideoProject, time: VideoTime,
                             size: VideoSize, to destination: URL) async throws {
        guard let context = Self.context else {
            throw VideoError.unsupportedFeature("A Metal-capable GPU is required for layer previews.")
        }
        let source: CIImage
        switch clip.source {
        case .text(let text, let style):
            source = try await AppleFrameRenderer.textImage(text, style: style, project: project,
                size: size, rasterSize: clip.textRasterSize(for: size))
        case .image(let url):
            guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
                  !image.extent.isEmpty, !image.extent.isInfinite else {
                throw VideoError.invalidMedia("Cannot decode the layer image.")
            }
            source = image
        case .video(let url):
            let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            generator.appliesPreferredTrackTransform = true
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            let sourceTime = try clip.sourceTime(at: time)
            source = CIImage(cgImage: try await generator.image(at: sourceTime.cmTime).image)
        case .audio:
            throw VideoError.invalidProject("Audio has no visual layer.")
        }
        try Task.checkCancellation()
        let canvas = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        let filtered = AppleFrameRenderer.apply(clip.filters, to: source)
        let fitted = AppleFrameRenderer.fit(filtered, transform: clip.transform, canvas: canvas)
        // PNG needs integral pixel bounds; display uses the original normalized layer size.
        let bounds = CGRect(x: 0, y: 0, width: max(1, Int((Double(size.width) * clip.transform.width).rounded())),
                            height: max(1, Int((Double(size.height) * clip.transform.height).rounded())))
        let clear = CIImage(color: CIColor.clear).cropped(to: bounds)
        try context.writePNGRepresentation(of: fitted.composited(over: clear).cropped(to: bounds), to: destination,
            format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
    }
    #endif
}
