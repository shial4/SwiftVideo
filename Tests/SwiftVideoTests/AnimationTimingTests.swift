// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct AnimationTimingTests {
    private func time(_ tenths: Int64) throws -> VideoTime { try VideoTime(value: tenths, timescale: 10) }

    @Test func bezierSolvesTimeCoordinateAndHandlesFlatTangents() throws {
        // x(t) = t^3, y(t) = 1 - (1-t)^3. At x=1/8, t=1/2, y=7/8.
        let curve = CubicBezierTiming(x1: 0, y1: 1, x2: 0, y2: 1)
        #expect(abs(curve.value(at: 0.125) - 0.875) < 1e-6)
        #expect(curve.value(at: -1) == 0 && curve.value(at: 2) == 1)
        let flat = CubicBezierTiming(x1: 1, y1: 0, x2: 0, y2: 1)
        #expect(abs(flat.value(at: 0.5) - 0.5) < 1e-5)
        let diagonal = CubicBezierTiming(x1: 0.1, y1: 0.1, x2: 0.8, y2: 0.8)
        for step in 0...100 { let t = Double(step) / 100; #expect(abs(diagonal.value(at: t) - t) < 1e-6) }
        let frames = try [Keyframe(time: .zero, value: 0, easing: .step, curve: curve), Keyframe(time: time(10), value: 1)]
        let value = try #require(KeyframeAnimation(property: .opacity, keyframes: frames).value(at: VideoTime(value: 1, timescale: 8)))
        #expect(abs(value - 0.875) < 1e-6)
    }

    @Test func repeatAndReverseRespectDelayCycleBoundariesAndFiniteEnd() throws {
        let frames = try [Keyframe(time: time(2), value: 0), Keyframe(time: time(6), value: 1)]
        func values(_ repetition: AnimationRepetition?, at times: [Int64]) throws -> [Double] {
            let animation = KeyframeAnimation(property: .opacity, keyframes: frames, repetition: repetition)
            return try times.map { try #require(animation.value(at: time($0))) }
        }
        let forward = try values(.count(2), at: [0, 2, 4, 6, 8, 10, 20])
        let reverse = try values(.count(1, autoreverses: true), at: [0, 2, 4, 6, 8, 10, 20])
        for (actual, expected) in zip(forward, [0.0, 0, 0.5, 0, 0.5, 1, 1]) { #expect(abs(actual - expected) < 1e-8) }
        for (actual, expected) in zip(reverse, [0.0, 0, 0.5, 1, 0.5, 0, 0]) { #expect(abs(actual - expected) < 1e-8) }
        #expect(abs(try values(.forever(), at: [20])[0] - 0.5) < 1e-8)
        #expect(abs(try values(.forever(autoreverses: true), at: [20])[0] - 0.5) < 1e-8)
        #expect(try values(nil, at: [20]) == [1])
        let rapid = try KeyframeAnimation(property: .opacity, keyframes: [
            Keyframe(time: .zero, value: 0), Keyframe(time: time(1), value: 1)
        ], repetition: .forever())
        for boundary in 1...100 { #expect(try rapid.value(at: time(Int64(boundary))) == 0) }
    }

    @Test func retimingTrimAndSplitKeepCurveAndRepeatPhase() async throws {
        let curve = CubicBezierTiming(x1: 0, y1: 1, x2: 0, y2: 1)
        let clip = try MediaClip.text("Title", duration: time(40)).animate(.opacity, keyframes: [
            Keyframe(time: .zero, value: 0, curve: curve), Keyframe(time: time(10), value: 1)
        ], repetition: .forever(autoreverses: true)).speed(.double)
        #expect(clip.animations[0].keyframes[0].curve == curve)
        #expect(clip.animations[0].repetition == .forever(autoreverses: true))
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [clip])]))
        _ = try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: time(2), duration: time(12)))])
        let project = try await editor.apply([.split(clip.id, at: time(8), rightID: UUID())])
        let first = try #require(project.tracks.first?.clips.first), second = try #require(project.tracks.first?.clips.last)
        for (edited, point) in [(first, try time(6)), (second, try time(12))] {
            #expect(try edited.visualTransform(at: point).opacity == clip.visualTransform(at: point).opacity)
        }
        #expect(try JSONDecoder().decode(VideoProject.self, from: JSONEncoder().encode(project)) == project)
    }

    @Test func oldAnimationDocumentsDecodeAndMalformedControlsFailValidation() throws {
        let frames = try [Keyframe(time: .zero, value: 0), Keyframe(time: time(10), value: 1)]
        let animation = KeyframeAnimation(property: .opacity, keyframes: frames)
        let encoded = try JSONEncoder().encode(animation)
        #expect(!String(decoding: encoded, as: UTF8.self).contains("repetition"))
        #expect(!String(decoding: encoded, as: UTF8.self).contains("curve"))
        #expect(try JSONDecoder().decode(KeyframeAnimation.self, from: encoded) == animation)
        func validate(_ keyframes: [Keyframe], repetition: AnimationRepetition?) throws {
            let clip = try MediaClip.text("Title", duration: time(20)).animate(.opacity, keyframes: keyframes, repetition: repetition)
            try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate()
        }
        #expect(throws: VideoError.self) { try validate(frames, repetition: .count(0)) }
        #expect(throws: VideoError.self) { try validate([frames[0]], repetition: .forever()) }
        for invalid in [Double.nan, .infinity, -0.1, 1.1] {
            #expect(throws: VideoError.self) { try validate([Keyframe(time: .zero, value: 0,
                curve: CubicBezierTiming(x1: invalid, y1: 0, x2: 1, y2: 1)), frames[1]], repetition: nil) }
        }
        let malformed = KeyframeAnimation(property: .opacity, keyframes: [frames[0]], repetition: .forever())
        #expect(try malformed.value(at: time(10)) == 0)
    }
}
