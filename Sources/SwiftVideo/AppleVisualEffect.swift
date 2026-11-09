// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(CoreImage)
import CoreImage
import Foundation

/// One instance per clip/filter/export, confined to the renderer's serial executor.
/// Return a lazy Core Image graph; the renderer evaluates it using its shared Metal CIContext.
/// Keep the input extent and premultiplied alpha. Do not read pixels back to the CPU.
public protocol AppleVisualEffectProcessor: AnyObject {
    func apply(to image: CIImage, context: EffectContext) throws -> CIImage
    /// Called exactly once after preparation, including failure and cancellation paths.
    func finish()
}

extension AppleVisualEffectProcessor {
    public func finish() {}
}

extension VisualEffectDefinition {
    public func apple(_ factory: @escaping @Sendable ([String: EffectValue]) throws -> any AppleVisualEffectProcessor) -> Self {
        var copy = self; copy.appleFactory = factory; return copy
    }
}

/// Export-owned processors. No processor or mutable filter instance is shared across exports.
final class AppleVisualEffects {
    private struct PreparedEffect {
        let processor: any AppleVisualEffectProcessor
        let clock: EffectClock
    }
    private var processors: [UUID: [Int: PreparedEffect]] = [:]

    init(clips: [MediaClip], registry: EffectRegistry) throws {
        do {
            for clip in clips {
                for (index, filter) in clip.filters.enumerated() {
                    guard case .custom(let reference) = filter else { continue }
                    let (definition, parameters) = try registry.resolve(reference, for: .apple)
                    guard let factory = definition.appleFactory else {
                        throw VideoError.unsupportedFeature("The custom effect has no Apple implementation.")
                    }
                    processors[clip.id, default: [:]][index] = try PreparedEffect(processor: factory(parameters), clock: EffectClock(clip: clip))
                }
            }
        } catch {
            finish()
            throw error
        }
    }

    func apply(to image: CIImage, clipID: UUID, filterIndex: Int, projectTime: Double) throws -> CIImage {
        guard let effect = processors[clipID]?[filterIndex] else {
            throw VideoError.renderingFailed("A custom visual effect was not prepared.")
        }
        let result = try effect.processor.apply(to: image, context: effect.clock.context(at: projectTime))
        guard !result.extent.isEmpty, !result.extent.isInfinite,
              result.extent == image.extent else {
            throw VideoError.renderingFailed("A custom visual effect must preserve its input image extent.")
        }
        return result
    }

    func finish() {
        for chain in processors.values { for effect in chain.values { effect.processor.finish() } }
        processors.removeAll()
    }
}
#endif
