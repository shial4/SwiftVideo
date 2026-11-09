// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension ChromaKey {
    var androidEffect: AndroidVisualEffect {
        AndroidVisualEffect(fragmentShader: """
            precision highp float;
            uniform sampler2D uTexSampler;
            uniform vec3 uKey;
            uniform vec2 uThreshold;
            varying vec2 vTexCoord;
            void main() {
                vec4 color = texture2D(uTexSampler, vTexCoord);
                float distance = length(color.rgb - uKey) / sqrt(3.0);
                float coverage = smoothstep(uThreshold.x, uThreshold.x + uThreshold.y, distance);
                gl_FragColor = vec4(color.rgb, color.a * coverage);
            }
            """, uniforms: ["uKey": linearColor.map(Float.init), "uThreshold": [Float(tolerance), Float(max(softness, 0.000001))]])
    }
}

extension VideoMask {
    var androidEffect: AndroidVisualEffect {
        AndroidVisualEffect(fragmentShader: """
            precision highp float;
            uniform sampler2D uTexSampler;
            uniform vec2 uTexelSize;
            uniform vec4 uBounds;
            uniform vec3 uMask;
            varying vec2 vTexCoord;
            void main() {
                vec2 point = (vec2(vTexCoord.x, 1.0 - vTexCoord.y) - uBounds.xy) / uBounds.zw;
                vec2 size = uBounds.zw / uTexelSize;
                float shortest = min(size.x, size.y);
                float edge = min(max(uMask.y * shortest, 1.0), shortest * 0.5);
                float inside;
                if (uMask.x > 0.5) {
                    inside = (1.0 - length((point - 0.5) * 2.0)) * shortest * 0.5;
                } else {
                    vec2 sides = min(point, 1.0 - point) * size;
                    inside = min(sides.x, sides.y);
                }
                float coverage = clamp(inside / edge, 0.0, 1.0);
                coverage = mix(coverage, 1.0 - coverage, uMask.z);
                vec4 color = texture2D(uTexSampler, vTexCoord);
                gl_FragColor = vec4(color.rgb, color.a * coverage);
            }
            """, uniforms: ["uBounds": [Float(bounds.x), Float(bounds.y), Float(bounds.width), Float(bounds.height)],
                             "uMask": [shape == .ellipse ? 1 : 0, Float(feather), inverted ? 1 : 0]])
    }
}
