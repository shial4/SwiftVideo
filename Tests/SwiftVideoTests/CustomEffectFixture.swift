// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SWIFTVIDEO_CORE_COVERAGE
import SwiftVideo
#if canImport(CoreImage)
import CoreImage
#endif

enum CustomEffectFixture {
    static let id = EffectIdentifier("test.channel-rotation")
    static let failingID = EffectIdentifier("test.failing-shader")

    static func failingRegistry() throws -> EffectRegistry {
        var definition = VisualEffectDefinition(failingID).android { _ in
            AndroidVisualEffect(fragmentShader: "This is not valid GLSL.")
        }
        #if canImport(CoreImage)
        definition = definition.apple { _ in FailingVisualEffect() }
        #endif
        return try EffectRegistry(visual: [definition])
    }

    static func registry() throws -> EffectRegistry {
        var definition = VisualEffectDefinition(id, parameters: [
            "amount": EffectParameter(.number, defaultValue: .number(1), range: 0...1),
            "opacity": EffectParameter(.number, defaultValue: .number(1), range: 0...1)
        ]).android { parameters in
            guard case .number(let amount) = parameters["amount"] else { throw VideoError.invalidProject("Missing amount") }
            guard case .number(let opacity) = parameters["opacity"] else { throw VideoError.invalidProject("Missing opacity") }
            return AndroidVisualEffect(fragmentShader: """
                precision mediump float;
                uniform sampler2D uTexSampler;
                uniform float uAmount;
                uniform float uOpacity;
                varying vec2 vTexCoord;
                void main() {
                    vec4 color = texture2D(uTexSampler, vTexCoord);
                    gl_FragColor = vec4(mix(color.rgb, color.gbr, uAmount), color.a * uOpacity);
                }
                """, uniforms: ["uAmount": [Float(amount)], "uOpacity": [Float(opacity)]])
        }
        #if canImport(CoreImage)
        definition = definition.apple { parameters in
            guard case .number(let amount) = parameters["amount"] else { throw VideoError.invalidProject("Missing amount") }
            guard case .number(let opacity) = parameters["opacity"] else { throw VideoError.invalidProject("Missing opacity") }
            return ChannelRotation(amount: amount, opacity: opacity)
        }
        #endif
        return try EffectRegistry(visual: [definition])
    }
}

#if canImport(CoreImage)
private final class FailingVisualEffect: AppleVisualEffectProcessor {
    func apply(to image: CIImage) throws -> CIImage { throw VideoError.renderingFailed("Custom effect failed") }
}

private final class ChannelRotation: AppleVisualEffectProcessor {
    private let amount: Double
    private let opacity: Double
    init(amount: Double, opacity: Double) { self.amount = amount; self.opacity = opacity }
    func apply(to image: CIImage) throws -> CIImage {
        image.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 1 - amount, y: amount, z: 0, w: 0),
            "inputGVector": CIVector(x: 0, y: 1 - amount, z: amount, w: 0),
            "inputBVector": CIVector(x: amount, y: 0, z: 1 - amount, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity)
        ])
    }
}
#endif
#endif
