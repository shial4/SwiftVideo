// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(Vision)
import CoreImage
import CoreVideo
import Vision
import SwiftVideo

/// Confined to the export executor. Vision selects its available compute devices;
/// Core Image downsamples and composites without CPU pixel iteration or readback.
final class ApplePersonSegmentation: AppleVisualEffectProcessor {
    private var handler: VNSequenceRequestHandler? = VNSequenceRequestHandler()
    private var request: VNGeneratePersonSegmentationRequest? = VNGeneratePersonSegmentationRequest()
    private let compositor: AppleSegmentationCompositor

    init(settings: SegmentationSettings) {
        request?.revision = VNGeneratePersonSegmentationRequestRevision1
        request?.qualityLevel = .balanced
        request?.outputPixelFormat = kCVPixelFormatType_OneComponent8
        compositor = AppleSegmentationCompositor(settings: settings)
    }

    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
        guard let handler, let request else { throw VideoError.renderingFailed("The person segmenter has finished.") }
        try Task.checkCancellation()
        let extent = image.extent
        let input = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: 256 / extent.width, y: 256 / extent.height))
        try handler.perform([request], on: input)
        try Task.checkCancellation()
        guard let buffer = request.results?.first?.pixelBuffer else {
            throw VideoError.renderingFailed("Vision returned no person confidence mask.")
        }
        let confidence = CIImage(cvPixelBuffer: buffer, options: [.colorSpace: NSNull()])
        return compositor.apply(mask: confidence, to: image)
    }

    func finish() { request?.cancel(); request = nil; handler = nil }
}

/// Both model adapters share the same confidence interpolation and alpha contract.
struct AppleSegmentationCompositor {
    private let threshold: [String: Any]

    init(settings: SegmentationSettings) {
        let scale = 1 / max(settings.softness, 0.000001)
        let vector = CIVector(x: scale, y: 0, z: 0, w: 0)
        threshold = ["inputRVector": vector, "inputGVector": vector, "inputBVector": vector,
                     "inputBiasVector": CIVector(x: -settings.threshold * scale, y: -settings.threshold * scale,
                                                 z: -settings.threshold * scale, w: 0)]
    }

    func apply(mask confidence: CIImage, to image: CIImage) -> CIImage {
        let extent = image.extent
        let smooth = CIVector(x: 0, y: 0, z: 3, w: -2)
        let mask = confidence.clampedToExtent()
            .transformed(by: CGAffineTransform(scaleX: extent.width / confidence.extent.width,
                                              y: extent.height / confidence.extent.height))
            .transformed(by: CGAffineTransform(translationX: extent.minX, y: extent.minY))
            .cropped(to: extent)
            .applyingFilter("CIColorMatrix", parameters: threshold)
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIColorPolynomial", parameters: [
                "inputRedCoefficients": smooth, "inputGreenCoefficients": smooth, "inputBlueCoefficients": smooth
            ])
        return image.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: extent), kCIInputMaskImageKey: mask
        ]).cropped(to: extent)
    }

}
#endif
