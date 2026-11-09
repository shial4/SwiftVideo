// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// An OpenGL ES 2.0 fragment shader compiled once on Media3's GL thread.
/// Read `uTexSampler` at `vTexCoord`. Output straight-alpha RGBA without changing the image size.
/// Optional renderer uniforms: `uTexelSize`, `uProjectTime`, `uEffectTime`, `uEffectDuration`,
/// `uSourceTime` and `uProgress`. Times are in seconds. Shader code comes only from your registry.
public struct AndroidVisualEffect: Encodable, Sendable {
    public let fragmentShader: String
    /// Float, vec2, vec3 or vec4 uniforms. Names must match active shader uniforms.
    public let uniforms: [String: [Float]]

    public init(fragmentShader: String, uniforms: [String: [Float]] = [:]) {
        self.fragmentShader = fragmentShader; self.uniforms = uniforms
    }

    func validate() throws {
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
