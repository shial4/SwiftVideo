// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MaskShape: String, Hashable, Codable, Sendable { case rectangle, ellipse }

/// A source-space mask applied before crop and placement. Coordinates have a top-left origin.
public struct VideoMask: Hashable, Codable, Sendable {
    public let shape: MaskShape
    public let bounds: VideoCrop
    /// Inward edge fade as a fraction of the mask's shortest side, in 0...0.5.
    /// A zero feather still uses a one-pixel antialiased edge.
    public let feather: Double
    public let inverted: Bool

    public init(shape: MaskShape = .ellipse, bounds: VideoCrop = VideoCrop(), feather: Double = 0, inverted: Bool = false) {
        self.shape = shape; self.bounds = bounds; self.feather = feather; self.inverted = inverted
    }

    func validate() throws {
        let b = bounds
        guard [b.x, b.y, b.width, b.height, feather].allSatisfy(\.isFinite),
              b.x >= 0, b.y >= 0, b.width > 0, b.height > 0,
              b.x + b.width <= 1, b.y + b.height <= 1, (0...0.5).contains(feather) else {
            throw VideoError.invalidProject("Mask bounds must fit within the source and feather must be between zero and 0.5.")
        }
    }
}

/// Removes an opaque sRGB key color using normalized linear-RGB distance.
/// Existing source alpha is multiplied by the key's smooth edge coverage.
public struct ChromaKey: Hashable, Codable, Sendable {
    public let color: VideoColor
    /// Colors within this distance are transparent; the maximum RGB distance is one.
    public let tolerance: Double
    /// Smooth transition width beyond tolerance. Both values must fit within 0...1.
    public let softness: Double

    public init(color: VideoColor = VideoColor(red: 0, green: 1, blue: 0), tolerance: Double = 0.1, softness: Double = 0.1) {
        self.color = color; self.tolerance = tolerance; self.softness = softness
    }

    func validate() throws {
        guard [color.red, color.green, color.blue, tolerance, softness].allSatisfy({ $0.isFinite && (0...1).contains($0) }),
              color.alpha == 1, tolerance + softness <= 1 else {
            throw VideoError.invalidProject("Chroma key requires an opaque color, normalized components and tolerance plus softness no greater than one.")
        }
    }

    var linearColor: [Double] {
        [color.red, color.green, color.blue].map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }
}
