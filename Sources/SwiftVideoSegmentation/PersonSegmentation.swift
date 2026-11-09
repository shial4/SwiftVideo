// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftVideo
#if os(Android)
import SwiftVideoSegmentationMedia3
#endif

/// Optional person-background removal. Models identify people, not arbitrary foreground objects.
/// Apple uses Vision or an app-supplied Core ML model. Android uses MediaPipe.
public enum PersonSegmentation {
    public static let identifier = EffectIdentifier("swiftvideo.person-segmentation", version: 1)

    /// GPU inference is the default. Select CPU explicitly for environments such
    /// as Android emulators whose GL driver cannot execute the model delegate.
    public enum AndroidCompute: Sendable { case gpu, cpu }

    /// Register once with the export service. Apple defaults to Vision on devices;
    /// supply the documented DeepLabV3 model to support the iOS Simulator. Android
    /// requires the MediaPipe Selfie Segmenter square model. Models are local only.
    public static func definition(appleModelURL: URL? = nil, androidModelURL: URL? = nil,
                                  androidCompute: AndroidCompute = .gpu) throws -> VisualEffectDefinition {
        let definition = VisualEffectDefinition(identifier, parameters: [
            "threshold": EffectParameter(.number, defaultValue: .number(0.4), range: 0...1),
            "softness": EffectParameter(.number, defaultValue: .number(0.2), range: 0...1)
        ])
        #if os(Android)
        guard let model = androidModelURL, model.isFileURL else {
            throw VideoError.invalidProject("Person segmentation requires a local Android model file URL.")
        }
        // Compute policy belongs to registration; reuse it for each clip processor.
        let useGPU = androidCompute == .gpu
        return definition.android { parameters in
            let settings = try SegmentationSettings(parameters)
            return AndroidVisualEffect(nativeFactory: {
                try Media3PersonSegmentation.makeEffect(modelPath: model.path,
                    threshold: settings.threshold, softness: settings.softness, useGPU: useGPU)
            })
        }
        #elseif canImport(Vision)
        if let model = appleModelURL {
            guard model.isFileURL else { throw VideoError.invalidProject("The Apple segmentation model must be a local file URL.") }
            return definition.apple { try AppleModelSegmentation(modelURL: model, settings: SegmentationSettings($0)) }
        }
        #if targetEnvironment(simulator)
        throw VideoError.unsupportedFeature("Vision person segmentation does not work in the iOS Simulator. Supply the documented DeepLabV3 Core ML model through appleModelURL.")
        #else
        return definition.apple { try ApplePersonSegmentation(settings: SegmentationSettings($0)) }
        #endif
        #else
        throw VideoError.unsupportedFeature("Person segmentation is unavailable on this platform.")
        #endif
    }

    /// Smoothly retain confidence values from threshold through threshold + softness.
    /// Both values must be in 0...1 and their sum must not exceed 1.
    public static func filter(threshold: Double = 0.4, softness: Double = 0.2) -> MediaFilter {
        .custom(EffectReference(identifier, parameters: ["threshold": .number(threshold), "softness": .number(softness)]))
    }
}

struct SegmentationSettings: Sendable {
    let threshold: Double
    let softness: Double

    init(_ parameters: [String: EffectValue]) throws {
        guard case .number(let threshold) = parameters["threshold"],
              case .number(let softness) = parameters["softness"],
              threshold.isFinite, softness.isFinite,
              (0...1).contains(threshold), (0...1).contains(softness), threshold + softness <= 1 else {
            throw VideoError.invalidProject("Segmentation threshold and softness must be finite, in 0...1, and sum to at most 1.")
        }
        self.threshold = threshold; self.softness = softness
    }
}
