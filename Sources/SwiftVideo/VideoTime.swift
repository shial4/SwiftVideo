// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Exact rational time. Arithmetic throws instead of overflowing or silently rounding.
public struct VideoTime: Hashable, Sendable, Comparable, Codable {
    public let value: Int64
    public let timescale: Int32

    public static let zero = VideoTime(normalizedValue: 0, timescale: 1)

    public init(value: Int64, timescale: Int32) throws {
        guard timescale > 0, value != .min else {
            throw VideoError.invalidTime("A positive timescale and a representable magnitude are required.")
        }
        let divisor = Self.gcd(abs(value), Int64(timescale))
        self.init(normalizedValue: value / divisor, timescale: Int32(Int64(timescale) / divisor))
    }

    public init(frames: Int64, rate: FrameRate) throws {
        let product = frames.multipliedReportingOverflow(by: Int64(rate.denominator))
        guard !product.overflow else { throw VideoError.timeOverflow }
        try self.init(value: product.partialValue, timescale: rate.numerator)
    }

    private init(normalizedValue: Int64, timescale: Int32) {
        value = normalizedValue
        self.timescale = timescale
    }

    /// Approximation for rendering APIs only. Editing and comparisons use rational time.
    public var seconds: Double { Double(value) / Double(timescale) }

    public func adding(_ other: VideoTime) throws -> VideoTime {
        let divisor = Self.gcd(Int64(timescale), Int64(other.timescale))
        let leftScale = Int64(other.timescale) / divisor
        let rightScale = Int64(timescale) / divisor
        let scale = Int64(timescale) * leftScale
        guard scale <= Int64(Int32.max) else { throw VideoError.timeOverflow }
        let lhs = value.multipliedReportingOverflow(by: leftScale)
        let rhs = other.value.multipliedReportingOverflow(by: rightScale)
        let sum = lhs.partialValue.addingReportingOverflow(rhs.partialValue)
        guard !lhs.overflow, !rhs.overflow, !sum.overflow else { throw VideoError.timeOverflow }
        return try VideoTime(value: sum.partialValue, timescale: Int32(scale))
    }

    public func subtracting(_ other: VideoTime) throws -> VideoTime {
        try adding(VideoTime(normalizedValue: -other.value, timescale: other.timescale))
    }

    public static func < (lhs: VideoTime, rhs: VideoTime) -> Bool {
        let left = lhs.value.multipliedFullWidth(by: Int64(rhs.timescale))
        let right = rhs.value.multipliedFullWidth(by: Int64(lhs.timescale))
        return left.high == right.high ? left.low < right.low : left.high < right.high
    }

    private static func gcd(_ a: Int64, _ b: Int64) -> Int64 {
        var a = a
        var b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    private enum CodingKeys: String, CodingKey { case value, timescale }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(value: values.decode(Int64.self, forKey: .value),
                      timescale: values.decode(Int32.self, forKey: .timescale))
    }
}

public struct FrameRate: Hashable, Sendable, Codable {
    public let numerator: Int32
    public let denominator: Int32

    public static let fps24 = FrameRate(validatedNumerator: 24, denominator: 1)
    public static let fps30 = FrameRate(validatedNumerator: 30, denominator: 1)
    public static let fps60 = FrameRate(validatedNumerator: 60, denominator: 1)

    public init(numerator: Int32, denominator: Int32 = 1) throws {
        guard numerator > 0, denominator > 0 else {
            throw VideoError.invalidTime("Frame rate components must be positive.")
        }
        var a = numerator
        var b = denominator
        while b != 0 { (a, b) = (b, a % b) }
        self.init(validatedNumerator: numerator / a, denominator: denominator / a)
    }

    private init(validatedNumerator: Int32, denominator: Int32) {
        numerator = validatedNumerator
        self.denominator = denominator
    }

    public var framesPerSecond: Double { Double(numerator) / Double(denominator) }

    private enum CodingKeys: String, CodingKey { case numerator, denominator }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(numerator: values.decode(Int32.self, forKey: .numerator),
                      denominator: values.decode(Int32.self, forKey: .denominator))
    }
}

/// A half-open interval: start is included, end is excluded.
public struct VideoTimeRange: Hashable, Sendable, Codable {
    public let start: VideoTime
    public let duration: VideoTime

    public init(start: VideoTime = .zero, duration: VideoTime) {
        self.start = start
        self.duration = duration
    }

    public var end: VideoTime { get throws { try start.adding(duration) } }

    public func contains(_ time: VideoTime) throws -> Bool {
        try time >= start && time < end
    }
}
