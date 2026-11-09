// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreImage)
import CoreImage
import Foundation

/// Built-in Core Image graphs let the shared Metal context fuse color operations.
/// No lookup table, CPU pixel loop, or texture readback is required.
final class AppleChromaKey: AppleVisualEffectProcessor {
    private let squaredDistance: [String: Any]
    private let threshold: [String: Any]

    init(_ key: ChromaKey) {
        let c = key.linearColor
        squaredDistance = [
            "inputRedCoefficients": CIVector(x: c[0] * c[0], y: -2 * c[0], z: 1, w: 0),
            "inputGreenCoefficients": CIVector(x: c[1] * c[1], y: -2 * c[1], z: 1, w: 0),
            "inputBlueCoefficients": CIVector(x: c[2] * c[2], y: -2 * c[2], z: 1, w: 0),
            "inputAlphaCoefficients": CIVector(x: 1, y: 0, z: 0, w: 0)
        ]
        let scale = 1 / max(key.softness, 0.000001)
        threshold = [
            "inputRVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputGVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputBVector": CIVector(x: scale, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: -key.tolerance * scale, y: -key.tolerance * scale, z: -key.tolerance * scale, w: 0)
        ]
    }

    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
        let sum = CIVector(x: 1.0 / 3, y: 1.0 / 3, z: 1.0 / 3, w: 0)
        let smooth = CIVector(x: 0, y: 0, z: 3, w: -2)
        let mask = image.applyingFilter("CIColorPolynomial", parameters: squaredDistance)
            .applyingFilter("CIColorMatrix", parameters: ["inputRVector": sum, "inputGVector": sum, "inputBVector": sum])
            .applyingFilter("CIGammaAdjust", parameters: ["inputPower": 0.5])
            .applyingFilter("CIColorMatrix", parameters: threshold)
            .applyingFilter("CIColorClamp")
            .applyingFilter("CIColorPolynomial", parameters: [
                "inputRedCoefficients": smooth, "inputGreenCoefficients": smooth, "inputBlueCoefficients": smooth
            ])
        return applyingMask(mask, to: image)
    }
}

final class AppleShapeMask: AppleVisualEffectProcessor {
    private let settings: VideoMask
    private var cachedMask: CIImage?
    init(_ settings: VideoMask) { self.settings = settings }

    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
        if cachedMask?.extent != image.extent { cachedMask = try makeMask(in: image.extent) }
        guard let mask = cachedMask else { throw VideoError.renderingFailed("Cannot prepare the shape mask.") }
        return applyingMask(mask, to: image)
    }

    private func makeMask(in extent: CGRect) throws -> CIImage {
        let b = settings.bounds
        let rect = CGRect(x: extent.minX + b.x * extent.width, y: extent.minY + (1 - b.y - b.height) * extent.height,
                          width: b.width * extent.width, height: b.height * extent.height)
        let shortest = min(rect.width, rect.height)
        let edge = min(max(settings.feather * shortest, 1), shortest / 2)
        var mask: CIImage
        switch settings.shape {
        case .ellipse:
            mask = try generate("CIRadialGradient", [
                "inputCenter": CIVector(x: 0, y: 0), "inputRadius0": 1 - edge * 2 / shortest, "inputRadius1": 1,
                "inputColor0": CIColor.white, "inputColor1": CIColor.black
            ]).transformed(by: CGAffineTransform(scaleX: rect.width / 2, y: rect.height / 2))
                .transformed(by: CGAffineTransform(translationX: rect.midX, y: rect.midY))
        case .rectangle:
            let pairs = [
                (CGPoint(x: rect.minX, y: 0), CGPoint(x: rect.minX + edge, y: 0)),
                (CGPoint(x: rect.maxX, y: 0), CGPoint(x: rect.maxX - edge, y: 0)),
                (CGPoint(x: 0, y: rect.minY), CGPoint(x: 0, y: rect.minY + edge)),
                (CGPoint(x: 0, y: rect.maxY), CGPoint(x: 0, y: rect.maxY - edge))
            ]
            mask = CIImage(color: .white)
            for (outside, inside) in pairs {
                let side = try generate("CILinearGradient", [
                    "inputPoint0": CIVector(cgPoint: outside), "inputPoint1": CIVector(cgPoint: inside),
                    "inputColor0": CIColor.black, "inputColor1": CIColor.white
                ])
                mask = mask.applyingFilter("CIMinimumCompositing", parameters: [kCIInputBackgroundImageKey: side])
            }
        }
        if settings.inverted { mask = mask.applyingFilter("CIColorInvert") }
        return mask.cropped(to: extent)
    }

    private func generate(_ name: String, _ parameters: [String: Any]) throws -> CIImage {
        guard let image = CIFilter(name: name, parameters: parameters)?.outputImage else {
            throw VideoError.renderingFailed("Cannot create \(name) for the shape mask.")
        }
        return image
    }
}

private func applyingMask(_ mask: CIImage, to image: CIImage) -> CIImage {
    image.applyingFilter("CIBlendWithMask", parameters: [
        kCIInputBackgroundImageKey: CIImage(color: .clear).cropped(to: image.extent), kCIInputMaskImageKey: mask
    ]).cropped(to: image.extent)
}
#endif
