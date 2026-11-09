// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A bounded cubic Bezier timing curve from (0, 0) to (1, 1).
/// All control coordinates are in 0...1, so opacity and positive scale stay valid.
public struct CubicBezierTiming: Hashable, Codable, Sendable {
    public let x1: Double, y1: Double, x2: Double, y2: Double

    public init(x1: Double, y1: Double, x2: Double, y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    public func value(at progress: Double) -> Double {
        let progress = min(1, max(0, progress))
        if progress == 0 || progress == 1 { return progress }
        // Solve x(t) before evaluating y(t). Directly evaluating y(progress) is
        // incorrect for nonuniform x controls. Bisection also handles flat tangents.
        var lower = 0.0, upper = 1.0
        for _ in 0..<24 {
            let middle = (lower + upper) / 2
            if coordinate(middle, x1, x2) < progress { lower = middle } else { upper = middle }
        }
        return coordinate((lower + upper) / 2, y1, y2)
    }

    func validate() throws {
        guard [x1, y1, x2, y2].allSatisfy({ $0.isFinite && (0...1).contains($0) }) else {
            throw VideoError.invalidProject("Bezier timing controls must be finite and between zero and one.")
        }
    }

    private func coordinate(_ t: Double, _ first: Double, _ second: Double) -> Double {
        let remaining = 1 - t
        return 3 * remaining * remaining * t * first + 3 * remaining * t * t * second + t * t * t
    }
}

/// A cycle is one forward pass, plus one backward pass when autoreversing.
public enum AnimationRepetition: Hashable, Codable, Sendable {
    case count(Int, autoreverses: Bool = false)
    case forever(autoreverses: Bool = false)

    func validate() throws {
        if case .count(let count, _) = self, count < 1 {
            throw VideoError.invalidProject("Animation repeat counts must be positive.")
        }
    }

    func sampleTime(_ time: Double, start: Double, end: Double) -> Double {
        let duration = end - start
        guard duration > 0, time > start else { return start }
        let count: Int?
        let reverse: Bool
        switch self {
        case .count(let value, let autoreverses): count = value; reverse = autoreverses
        case .forever(let autoreverses): count = nil; reverse = autoreverses
        }
        let cycle = duration * (reverse ? 2 : 1)
        let elapsed = time - start
        var cycles = elapsed / cycle
        // Rational timeline boundaries can land a few floating-point ulps below
        // their integer cycle after conversion to seconds (for example 0.3 / 0.1).
        // Snap only that conversion error so a repeat starts on the correct frame.
        let nearest = cycles.rounded()
        if abs(cycles - nearest) <= max(cycles.ulp, nearest.ulp) * 4 { cycles = nearest }
        if let count, cycles >= Double(count) { return reverse ? start : end }
        var phase = (cycles - cycles.rounded(.down)) * cycle
        if reverse, phase > duration { phase = cycle - phase }
        return start + phase
    }
}
