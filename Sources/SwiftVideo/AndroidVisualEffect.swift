// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
#if os(Android)
import SwiftVideoMedia3
#endif

/// An OpenGL ES 2.0 fragment shader compiled once on Media3's GL thread.
/// Read `uTexSampler` at `vTexCoord`. Output straight-alpha RGBA without changing the image size.
/// Optional renderer uniforms: `uTexelSize`, `uProjectTime`, `uEffectTime`, `uEffectDuration`,
/// `uSourceTime` and `uProgress`. Times are in seconds. Shader code comes only from your registry.
public struct AndroidVisualEffect: Encodable, Sendable {
    public let fragmentShader: String
    /// Float, vec2, vec3 or vec4 uniforms. Names must match active shader uniforms.
    public let uniforms: [String: [Float]]
    #if os(Android)
    let nativeFactory: (@Sendable () throws -> Media3VisualEffect)?
    #endif

    public init(fragmentShader: String, uniforms: [String: [Float]] = [:]) {
        self.fragmentShader = fragmentShader; self.uniforms = uniforms
        #if os(Android)
        nativeFactory = nil
        #endif
    }

    #if os(Android)
    /// Adapts an application-owned Media3 effect, including optional ML processors.
    /// Called once per clip/filter/export on Media3's application looper. The returned
    /// effect creates and releases its GPU resources on Media3's GL thread.
    /// Only the registered factory can supply native code; project JSON cannot.
    public init(nativeFactory: @escaping @Sendable () throws -> Media3VisualEffect) {
        fragmentShader = ""; uniforms = [:]; self.nativeFactory = nativeFactory
    }
    #endif

    private enum CodingKeys: String, CodingKey { case fragmentShader, uniforms }

    public func encode(to encoder: any Encoder) throws {
        #if os(Android)
        guard nativeFactory == nil else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath,
                debugDescription: "Native effect factories cannot be serialized. Encode the project's effect reference instead."))
        }
        #endif
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(fragmentShader, forKey: .fragmentShader)
        try values.encode(uniforms, forKey: .uniforms)
    }

    func validate() throws {
        #if os(Android)
        if nativeFactory != nil { return }
        #endif
        guard !fragmentShader.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw VideoError.invalidProject("A custom Android effect requires a fragment shader.")
        }
        let reserved: Set<String> = ["uTexSampler", "uTexelSize", "uProjectTime", "uEffectTime", "uEffectDuration", "uSourceTime", "uProgress"]
        for (name, values) in uniforms {
            guard !name.isEmpty, !reserved.contains(name),
                  (1...4).contains(values.count), values.allSatisfy(\.isFinite) else {
                throw VideoError.invalidProject("Custom shader uniforms require a non-reserved name and 1...4 finite float components.")
            }
        }
    }
}
