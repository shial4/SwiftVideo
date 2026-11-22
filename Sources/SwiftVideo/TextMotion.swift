// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum TextMotionUnit: String, Hashable, Codable, Sendable { case word, character }

/// Per-word or per-grapheme motion inside the text layer, before its clip transform.
/// Translation is relative to the text layer's width/height, with positive y downward.
public struct TextMotion: Hashable, Codable, Sendable {
    public let unit: TextMotionUnit
    public let stagger: VideoTime
    public let animations: [KeyframeAnimation]

    public init(unit: TextMotionUnit = .word, stagger: VideoTime = .zero, animations: [KeyframeAnimation]) {
        self.unit = unit; self.stagger = stagger; self.animations = animations
    }

    public static func typewriter(stagger: VideoTime, unit: TextMotionUnit = .character) -> Self {
        Self(unit: unit, stagger: stagger, animations: [])
    }

    public static func fadeUp(duration: VideoTime, stagger: VideoTime = .zero, unit: TextMotionUnit = .word,
                              distance: Double = 0.1) -> Self {
        Self(unit: unit, stagger: stagger, animations: [
            KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: duration, value: 1)]),
            KeyframeAnimation(property: .y, keyframes: [Keyframe(time: .zero, value: distance, easing: .easeOut), Keyframe(time: duration, value: 0)])
        ])
    }

    public static func pop(duration: VideoTime, stagger: VideoTime = .zero, unit: TextMotionUnit = .word) throws -> Self {
        let peak = try duration.scaled(numerator: 3, denominator: 4)
        return Self(unit: unit, stagger: stagger, animations: [
            KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: peak, value: 1)]),
            KeyframeAnimation(property: .scale, keyframes: [Keyframe(time: .zero, value: 0.6, easing: .easeOut),
                Keyframe(time: peak, value: 1.08, easing: .easeInOut), Keyframe(time: duration, value: 1)])
        ])
    }

    /// Time is the original clip's effect time. Units are indexed in logical text order.
    public func transform(forUnit index: Int, at time: VideoTime) throws -> VisualTransform {
        guard index >= 0, index < Self.maximumUnits else { throw VideoError.invalidProject("Text motion unit is out of range.") }
        let local = try time.subtracting(delay(forUnit: index))
        guard local >= .zero else { return VisualTransform(x: 0, y: 0, opacity: 0) }
        return VisualTransform(x: 0, y: 0).applying(animations, at: local)
    }

    // Bound per-title preparation and per-frame transform work on both renderers.
    static let maximumUnits = 128
    struct Range: Encodable, Equatable, Sendable { let start: Int; let length: Int }

    func ranges(in text: String) -> [Range] {
        var ranges: [Range] = []
        var offset = 0
        var wordStart: Int?
        for character in text {
            let length = String(character).utf16.count
            if character.isWhitespace {
                if let start = wordStart { ranges.append(Range(start: start, length: offset - start)); wordStart = nil }
            } else if unit == .character { ranges.append(Range(start: offset, length: length)) }
            else if wordStart == nil { wordStart = offset }
            offset += length
        }
        if let start = wordStart { ranges.append(Range(start: start, length: offset - start)) }
        return ranges
    }

    func validate(text: String, duration: VideoTime) throws {
        let count = ranges(in: text).count
        guard count > 0, count <= Self.maximumUnits, stagger >= .zero else {
            throw VideoError.invalidProject("Motion titles require 1...128 non-whitespace units and nonnegative stagger.")
        }
        try validateAnimations(animations, duration: duration)
        let last = animations.flatMap(\.keyframes).map(\.time).max() ?? .zero
        guard try delay(forUnit: count - 1).adding(last) <= duration else {
            throw VideoError.invalidProject("The final text unit's first animation pass must fit within the original clip duration.")
        }
    }

    private func delay(forUnit index: Int) throws -> VideoTime {
        index == 0 ? .zero : try stagger.scaled(numerator: Int64(index), denominator: 1)
    }

    func retimed(_ scale: (VideoTime) throws -> VideoTime) rethrows -> Self {
        try Self(unit: unit, stagger: scale(stagger), animations: animations.map { try $0.retimed(scale) })
    }
}

extension VisualTransform {
    func applying(_ animations: [KeyframeAnimation], at time: VideoTime) -> Self {
        var x = x, y = y, scale = scale, rotation = rotation, opacity = opacity
        for animation in animations {
            guard let value = animation.value(at: time) else { continue }
            switch animation.property {
            case .x: x = value
            case .y: y = value
            case .scale: scale = value
            case .rotation: rotation = value
            case .opacity: opacity = value
            }
        }
        return Self(x: x, y: y, width: width, height: height, scale: scale, rotation: rotation, opacity: opacity,
                    crop: crop, contentMode: contentMode)
    }
}

extension KeyframeAnimation {
    func retimed(_ scale: (VideoTime) throws -> VideoTime) rethrows -> Self {
        try Self(property: property, keyframes: keyframes.map {
            Keyframe(time: try scale($0.time), value: $0.value, easing: $0.easing, curve: $0.curve)
        }, repetition: repetition)
    }
}
