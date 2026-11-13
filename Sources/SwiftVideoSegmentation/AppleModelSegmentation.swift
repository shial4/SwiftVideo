// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreML)
import CoreImage
import CoreML
import Metal
import SwiftVideo

/// Adapter for Apple's published DeepLabV3 model. The model selects CPU/GPU/ANE;
/// Metal converts its integer class map to alpha without a CPU per-pixel loop.
final class AppleModelSegmentation: AppleVisualEffectProcessor {
    private var model: MLModel?
    private var compiledURL: URL?
    private let queue: any MTLCommandQueue
    private let pipeline: any MTLComputePipelineState
    private let labels: any MTLBuffer
    private let mask: any MTLTexture
    private let input: CVPixelBuffer
    private let context: CIContext
    private let compositor: AppleSegmentationCompositor

    init(modelURL: URL, settings: SegmentationSettings) throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue(),
              let labels = device.makeBuffer(length: 513 * 513 * MemoryLayout<Int32>.stride, options: .storageModeShared) else {
            throw VideoError.unsupportedFeature("Core ML segmentation requires a Metal device.")
        }
        self.queue = queue; self.labels = labels
        let library = try device.makeLibrary(source: """
            #include <metal_stdlib>
            using namespace metal;
            kernel void personMask(device const int *labels [[buffer(0)]],
                                   texture2d<float, access::write> mask [[texture(0)]],
                                   uint2 position [[thread_position_in_grid]]) {
                if (position.x >= 513 || position.y >= 513) return;
                float alpha = labels[position.y * 513 + position.x] == 15 ? 1.0 : 0.0;
                mask.write(float4(alpha), position);
            }
            """, options: nil)
        guard let function = library.makeFunction(name: "personMask") else {
            throw VideoError.renderingFailed("The person-mask Metal kernel is unavailable.")
        }
        pipeline = try device.makeComputePipelineState(function: function)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .r8Unorm, width: 513, height: 513, mipmapped: false)
        descriptor.usage = [.shaderRead, .shaderWrite]
        guard let mask = device.makeTexture(descriptor: descriptor) else {
            throw VideoError.renderingFailed("Unable to allocate the person-mask texture.")
        }
        self.mask = mask
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, 513, 513, kCVPixelFormatType_32BGRA,
                                        [kCVPixelBufferMetalCompatibilityKey: true,
                                         kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &buffer)
        guard status == kCVReturnSuccess, let buffer else {
            throw VideoError.renderingFailed("Unable to allocate the segmentation input buffer.")
        }
        input = buffer
        context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
        compositor = AppleSegmentationCompositor(settings: settings)
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .all
        let compiled = modelURL.pathExtension == "mlmodel" ? try MLModel.compileModel(at: modelURL) : modelURL
        do {
            let model = try MLModel(contentsOf: compiled, configuration: configuration)
            let image = model.modelDescription.inputDescriptionsByName["image"]?.imageConstraint
            let output = model.modelDescription.outputDescriptionsByName["semanticPredictions"]?.multiArrayConstraint
            guard image?.pixelsWide == 513, image?.pixelsHigh == 513,
                  output?.dataType == .int32, output?.shape == [513, 513] else {
                throw VideoError.invalidProject("Use the documented DeepLabV3 model with a 513x513 image and Int32 semanticPredictions output.")
            }
            self.model = model
            compiledURL = compiled == modelURL ? nil : compiled
        } catch {
            if compiled != modelURL { try? FileManager.default.removeItem(at: compiled) }
            throw error
        }
    }

    func apply(to image: CIImage, context effect: EffectContext) throws -> CIImage {
        guard let model else { throw VideoError.renderingFailed("The person segmenter has finished.") }
        try Task.checkCancellation()
        let extent = image.extent
        let resized = image.transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: 513 / extent.width, y: 513 / extent.height))
        context.render(resized, to: input, bounds: CGRect(x: 0, y: 0, width: 513, height: 513),
                       colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!)
        let prediction = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["image": MLFeatureValue(pixelBuffer: input)]))
        guard let classes = prediction.featureValue(for: "semanticPredictions")?.multiArrayValue,
              classes.dataType == .int32, classes.shape == [513, 513], classes.strides == [513, 1] else {
            throw VideoError.renderingFailed("The segmentation model returned an unsupported class map.")
        }
        try Task.checkCancellation()
        // Core ML exposes class indices through a CPU-addressable array. Copy a
        // bounded 1 MB map once; class selection and all pixel math run on Metal.
        labels.contents().copyMemory(from: classes.dataPointer, byteCount: labels.length)
        guard let command = queue.makeCommandBuffer(), let encoder = command.makeComputeCommandEncoder() else {
            throw VideoError.renderingFailed("Unable to encode the person-mask GPU pass.")
        }
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(labels, offset: 0, index: 0)
        encoder.setTexture(mask, index: 0)
        encoder.dispatchThreads(MTLSize(width: 513, height: 513, depth: 1),
                                threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()
        if let error = command.error { throw error }
        guard let confidence = CIImage(mtlTexture: mask, options: [.colorSpace: NSNull()]) else {
            throw VideoError.renderingFailed("Unable to read the person-mask GPU texture.")
        }
        let upright = confidence.transformed(by: CGAffineTransform(scaleX: 1, y: -1))
            .transformed(by: CGAffineTransform(translationX: 0, y: 513))
        return compositor.apply(mask: upright, to: image)
    }

    func finish() {
        model = nil
        if let compiledURL { try? FileManager.default.removeItem(at: compiledURL) }
        compiledURL = nil
    }

    deinit { if let compiledURL { try? FileManager.default.removeItem(at: compiledURL) } }
}
#endif
