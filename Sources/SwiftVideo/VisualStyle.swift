// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public struct VideoSize: Hashable, Codable, Sendable {
    public let width: Int
    public let height: Int
    public init(width: Int, height: Int) { self.width = width; self.height = height }
    public static let hd1080 = VideoSize(width: 1920, height: 1080)
}

/// Straight-alpha sRGB components in the closed range 0...1.
public struct VideoColor: Hashable, Codable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }
    public static let black = VideoColor(red: 0, green: 0, blue: 0)
    public static let white = VideoColor(red: 1, green: 1, blue: 1)
    public static let clear = VideoColor(red: 0, green: 0, blue: 0, alpha: 0)
}

/// Normalized source crop with top-left origin.
public struct VideoCrop: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public init(x: Double = 0, y: Double = 0, width: Double = 1, height: Double = 1) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
}

public enum ContentMode: String, Codable, Sendable { case fit, fill, stretch }

/// Center position and size are normalized to the canvas. Rotation is clockwise in degrees.
public struct VisualTransform: Hashable, Codable, Sendable {
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let scale: Double
    public let rotation: Double
    public let opacity: Double
    public let crop: VideoCrop
    public let contentMode: ContentMode

    public init(x: Double = 0.5, y: Double = 0.5, width: Double = 1, height: Double = 1,
                scale: Double = 1, rotation: Double = 0, opacity: Double = 1,
                crop: VideoCrop = VideoCrop(), contentMode: ContentMode = .fit) {
        self.x = x; self.y = y; self.width = width; self.height = height
        self.scale = scale; self.rotation = rotation; self.opacity = opacity
        self.crop = crop; self.contentMode = contentMode
    }
}

public enum MediaFilter: Hashable, Codable, Sendable {
    case brightness(Double)
    case contrast(Double)
    case saturation(Double)
    case gaussianBlur(Double)
    case sepia(Double)
}

public enum TextAlignment: String, Codable, Sendable { case leading, center, trailing }

public struct TextShadow: Hashable, Codable, Sendable {
    public let color: VideoColor
    public let radius: Double
    public let x: Double
    public let y: Double
    public init(color: VideoColor = .black, radius: Double = 2, x: Double = 1, y: Double = 1) {
        self.color = color; self.radius = radius; self.x = x; self.y = y
    }
}

public struct TextStyle: Hashable, Codable, Sendable {
    /// A platform font name, or a font file URL to load a supplied custom font on both platforms.
    public let fontName: String?
    public let fontURL: URL?
    /// Size in project canvas pixels; scales when export resolution differs.
    public let fontSize: Double
    public let color: VideoColor
    public let alignment: TextAlignment
    public let shadow: TextShadow?
    public init(fontName: String? = nil, fontURL: URL? = nil, fontSize: Double = 48,
                color: VideoColor = .white, alignment: TextAlignment = .center, shadow: TextShadow? = nil) {
        self.fontName = fontName; self.fontURL = fontURL; self.fontSize = fontSize
        self.color = color; self.alignment = alignment; self.shadow = shadow
    }
}

public enum AnimationProperty: String, Codable, Sendable, CaseIterable {
    case x, y, scale, rotation, opacity
}

public enum Easing: String, Codable, Sendable {
    case linear, easeIn, easeOut, easeInOut, step

    public func value(at progress: Double) -> Double {
        let t = min(1, max(0, progress))
        switch self {
        case .linear: return t
        case .easeIn: return t * t
        case .easeOut: return t * (2 - t)
        case .easeInOut: return t * t * (3 - 2 * t)
        case .step: return t < 1 ? 0 : 1
        }
    }
}

public struct Keyframe: Hashable, Codable, Sendable {
    public let time: VideoTime
    public let value: Double
    /// Easing from this keyframe to the next.
    public let easing: Easing
    public init(time: VideoTime, value: Double, easing: Easing = .linear) {
        self.time = time; self.value = value; self.easing = easing
    }
}

public struct KeyframeAnimation: Hashable, Codable, Sendable {
    public let property: AnimationProperty
    public let keyframes: [Keyframe]
    public init(property: AnimationProperty, keyframes: [Keyframe]) {
        self.property = property; self.keyframes = keyframes
    }

    /// The caller validates sorted, unique keyframe times before rendering.
    public func value(at time: VideoTime) -> Double? {
        guard let first = keyframes.first, let last = keyframes.last else { return nil }
        if time <= first.time { return first.value }
        if time >= last.time { return last.value }
        for (left, right) in zip(keyframes, keyframes.dropFirst()) where time < right.time {
            let t = (time.seconds - left.time.seconds) / (right.time.seconds - left.time.seconds)
            return left.value + (right.value - left.value) * left.easing.value(at: t)
        }
        return last.value
    }
}
