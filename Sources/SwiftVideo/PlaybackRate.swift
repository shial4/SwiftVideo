// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// Constant, forward playback speed. Clip and track rates multiply; their product must be 0.25...4.
public struct PlaybackRate: Hashable, Codable, Sendable {
    public let numerator: Int32
    public let denominator: Int32

    public static let quarter = PlaybackRate(validated: 1, denominator: 4)
    public static let half = PlaybackRate(validated: 1, denominator: 2)
    public static let normal = PlaybackRate(validated: 1, denominator: 1)
    public static let double = PlaybackRate(validated: 2, denominator: 1)
    public static let quadruple = PlaybackRate(validated: 4, denominator: 1)

    public init(numerator: Int32, denominator: Int32 = 1) throws {
        guard numerator > 0, denominator > 0,
              Int64(numerator) * 4 >= Int64(denominator), Int64(numerator) <= Int64(denominator) * 4 else {
            throw VideoError.invalidProject("Playback speed must be between 0.25 and 4.")
        }
        let divisor = VideoTime.gcd(Int64(numerator), Int64(denominator))
        self.init(validated: Int32(Int64(numerator) / divisor), denominator: Int32(Int64(denominator) / divisor))
    }

    private init(validated numerator: Int32, denominator: Int32) {
        self.numerator = numerator; self.denominator = denominator
    }

    public var multiplier: Double { Double(numerator) / Double(denominator) }

    public func combined(with other: PlaybackRate) throws -> PlaybackRate {
        let a = VideoTime.gcd(Int64(numerator), Int64(other.denominator))
        let b = VideoTime.gcd(Int64(other.numerator), Int64(denominator))
        let n = (Int64(numerator) / a) * (Int64(other.numerator) / b)
        let d = (Int64(denominator) / b) * (Int64(other.denominator) / a)
        guard n <= Int32.max, d <= Int32.max else { throw VideoError.timeOverflow }
        return try PlaybackRate(numerator: Int32(n), denominator: Int32(d))
    }

    private enum CodingKeys: String, CodingKey { case numerator, denominator }
    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(numerator: values.decode(Int32.self, forKey: .numerator),
                      denominator: values.decode(Int32.self, forKey: .denominator))
    }
}

extension VideoTime {
    /// Exact multiplication, cancelling factors before checked arithmetic.
    public func scaled(by rate: PlaybackRate) throws -> VideoTime {
        try scaled(numerator: Int64(rate.numerator), denominator: Int64(rate.denominator))
    }

    func scaled(numerator: Int64, denominator: Int64) throws -> VideoTime {
        guard numerator > 0, denominator > 0 else { throw VideoError.invalidTime("Scale must be positive.") }
        if value == 0 { return .zero }
        let common = Self.gcd(numerator, denominator)
        let n = numerator / common
        let d = denominator / common
        let a = Self.gcd(abs(value), d)
        let b = Self.gcd(Int64(timescale), n)
        let product = (value / a).multipliedReportingOverflow(by: n / b)
        let scale = (Int64(timescale) / b).multipliedReportingOverflow(by: d / a)
        guard !product.overflow, product.partialValue != .min, !scale.overflow, scale.partialValue <= Int32.max else {
            throw VideoError.timeOverflow
        }
        return try VideoTime(value: product.partialValue, timescale: Int32(scale.partialValue))
    }
}
