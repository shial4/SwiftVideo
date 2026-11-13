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
    static let clockID = EffectIdentifier("test.effect-clock")

    /// Independent oracle for an original 1.6-second effect starting at project time 0.2.
    static func clockRegistry() throws -> EffectRegistry {
        var definition = VisualEffectDefinition(clockID).android { _ in
            AndroidVisualEffect(fragmentShader: """
                precision highp float;
                uniform float uProjectTime;
                uniform float uEffectTime;
                uniform float uEffectDuration;
                uniform float uSourceTime;
                uniform float uProgress;
                uniform vec2 uTexelSize;
                void main() {
                    bool valid = abs(uEffectTime - (uProjectTime - 0.2)) < 0.01
                        && abs(uEffectDuration - 1.6) < 0.01
                        && abs(uSourceTime - uProjectTime * 0.5) < 0.01
                        && abs(uProgress - uEffectTime / 1.6) < 0.01
                        && uTexelSize.x > 0.0 && uTexelSize.y > 0.0;
                    gl_FragColor = !valid ? vec4(1.0, 0.0, 0.0, 1.0)
                        : (uEffectTime < 0.8 ? vec4(0.0, 1.0, 0.0, 1.0) : vec4(0.0, 0.0, 1.0, 1.0));
                }
                """)
        }
        #if canImport(CoreImage)
        definition = definition.apple { _ in ClockVisualEffect() }
        #endif
        return try EffectRegistry(visual: [definition])
    }

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
private final class ClockVisualEffect: AppleVisualEffectProcessor {
    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
        let valid = abs(context.effectTime - (context.projectTime - 0.2)) < 0.01
            && abs(context.effectDuration - 1.6) < 0.01
            && abs(context.sourceTime - context.projectTime * 0.5) < 0.01
            && abs(context.progress - context.effectTime / 1.6) < 0.01
        let color: CIColor = !valid ? .red : (context.effectTime < 0.8 ? .green : .blue)
        return CIImage(color: color).cropped(to: image.extent)
    }
}

private final class FailingVisualEffect: AppleVisualEffectProcessor {
    func apply(to image: CIImage, context: EffectContext) throws -> CIImage { throw VideoError.renderingFailed("Custom effect failed") }
}

private final class ChannelRotation: AppleVisualEffectProcessor {
    private let amount: Double
    private let opacity: Double
    init(amount: Double, opacity: Double) { self.amount = amount; self.opacity = opacity }
    func apply(to image: CIImage, context: EffectContext) throws -> CIImage {
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
