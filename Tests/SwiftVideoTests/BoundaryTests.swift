// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
@testable import SwiftVideo

@Suite struct BoundaryTests {
    private func time(_ value: Int64) throws -> VideoTime { try VideoTime(value: value, timescale: 1) }

    @Test func rationalTimeRejectsInvalidAndOverflowingInput() throws {
        #expect(throws: VideoError.self) { try VideoTime(value: .min, timescale: 1) }
        #expect(throws: VideoError.self) { try VideoTime(value: 1, timescale: -1) }
        #expect(throws: VideoError.self) { try FrameRate(numerator: 0) }
        #expect(throws: VideoError.self) { try FrameRate(numerator: 30, denominator: 0) }
        let rate = try FrameRate(numerator: 30_000, denominator: 1_001)
        #expect(throws: VideoError.timeOverflow) { try VideoTime(frames: .max, rate: rate) }
        let a = try VideoTime(value: 1, timescale: 65_537)
        let b = try VideoTime(value: 1, timescale: 65_539)
        #expect(throws: VideoError.timeOverflow) { try a.adding(b) }
        #expect(try time(-2) < time(-1))
        #expect(try time(0).subtracting(time(2)) == time(-2))
        let malformed = Data(#"{"numerator":30,"denominator":0}"#.utf8)
        #expect(throws: VideoError.self) { try JSONDecoder().decode(FrameRate.self, from: malformed) }
    }

    @Test(arguments: [Easing.linear, .easeIn, .easeOut, .easeInOut, .step])
    func easingClampsAndInterpolatesMonotonically(_ easing: Easing) {
        #expect(easing.value(at: -1) == 0)
        #expect(easing.value(at: 2) == 1)
        let values = (0...20).map { easing.value(at: Double($0) / 20) }
        #expect(zip(values, values.dropFirst()).allSatisfy { $0 <= $1 })
        if easing == .step { #expect(easing.value(at: 0.99) == 0) }
    }

    @Test func animationHoldsEndpointsAndSamplesEveryProperty() throws {
        let frames = [Keyframe(time: try time(1), value: 0.25), Keyframe(time: try time(3), value: 0.75)]
        let animations = AnimationProperty.allCases.map { KeyframeAnimation(property: $0, keyframes: frames) }
        let clip = MediaClip(source: .text("Title", TextStyle()), duration: try time(4), animations: animations)
        let transform = try clip.visualTransform(at: time(2))
        #expect([transform.x, transform.y, transform.scale, transform.rotation, transform.opacity] == Array(repeating: 0.5, count: 5))
        #expect(animations[0].value(at: .zero) == 0.25)
        #expect(try animations[0].value(at: time(4)) == 0.75)
        #expect(KeyframeAnimation(property: .x, keyframes: []).value(at: .zero) == nil)
    }

    @Test func audioEnvelopeHonorsMuteFadesAndHalfOpenEnd() throws {
        let audio = AudioSettings(volume: 0.8, fadeIn: try time(2), fadeOut: try time(2))
        #expect(try audio.gain(at: time(-1), duration: time(8)) == 0)
        #expect(try audio.gain(at: time(1), duration: time(8)) == 0.4)
        #expect(try audio.gain(at: time(4), duration: time(8)) == 0.8)
        #expect(try audio.gain(at: time(7), duration: time(8)) == 0.4)
        #expect(try audio.gain(at: time(8), duration: time(8)) == 0)
        #expect(try AudioSettings(isMuted: true).gain(at: time(1), duration: time(8)) == 0)
    }

    @Test func trackAndClipEditsPreserveIdentityAndRejectMissingTargets() async throws {
        let track = MediaTrack(name: "Titles")
        let clip = MediaClip(source: .text("Before", TextStyle()), duration: try time(2))
        let editor = try VideoEditor()
        _ = try await editor.apply([.addTrack(track), .addClip(clip, trackID: track.id)])
        let replacement = MediaClip(id: clip.id, source: .text("After", TextStyle()), duration: try time(2))
        let replaced = try await editor.apply([.replaceClip(replacement)])
        #expect(replaced.tracks[0].clips == [replacement])
        let missing = UUID()
        await #expect(throws: VideoError.missingClip(missing)) { try await editor.apply([.removeClip(missing)]) }
        await #expect(throws: VideoError.missingTrack(missing)) { try await editor.apply([.removeTrack(missing)]) }
        #expect(await editor.snapshot() == replaced)
        let empty = try await editor.apply([.removeClip(clip.id), .removeTrack(track.id)])
        #expect(empty.tracks.isEmpty)
    }

    @Test(arguments: [Int64(0), 2, 3, -1])
    func splitRejectsEndpointsAndOutsideTimes(_ split: Int64) async throws {
        let clip = MediaClip(source: .text("A", TextStyle()), duration: try time(2))
        let project = VideoProject(tracks: [MediaTrack(clips: [clip])])
        let editor = try VideoEditor(project: project)
        await #expect(throws: VideoError.self) { try await editor.apply([.split(clip.id, at: time(split), rightID: UUID())]) }
        #expect(await editor.snapshot() == project)
    }

    @Test func invalidTrimAndDuplicateTrackAreTransactional() async throws {
        let clip = MediaClip(source: .text("A", TextStyle()), duration: try time(2))
        let track = MediaTrack(clips: [clip])
        let initial = VideoProject(tracks: [track])
        let editor = try VideoEditor(project: initial)
        await #expect(throws: VideoError.self) {
            try await editor.apply([.trim(clip.id, keeping: VideoTimeRange(start: time(1), duration: time(2)))])
        }
        await #expect(throws: VideoError.self) { try await editor.apply([.addTrack(track)]) }
        #expect(await editor.snapshot() == initial)
    }

    @Test func malformedVisualAndAudioInputIsRejectedBeforeRendering() throws {
        let duration = try time(2)
        let text = MediaSource.text("Title", TextStyle())
        let invalid: [MediaClip] = [
            MediaClip(source: text, duration: .zero),
            MediaClip(source: text, start: try time(-1), duration: duration),
            MediaClip(source: .image(URL(string: "ftp://example.com/a.png")!), duration: duration),
            MediaClip(source: .text("", TextStyle()), duration: duration),
            MediaClip(source: .text("A", TextStyle(fontSize: .nan)), duration: duration),
            MediaClip(source: .text("A", TextStyle(fontURL: URL(string: "https://example.com/font.ttf"))), duration: duration),
            MediaClip(source: .text("A", TextStyle(shadow: TextShadow(radius: -1))), duration: duration),
            MediaClip(source: text, duration: duration, transform: VisualTransform(x: .infinity)),
            MediaClip(source: text, duration: duration, transform: VisualTransform(scale: 0)),
            MediaClip(source: text, duration: duration, transform: VisualTransform(crop: VideoCrop(x: 0.9, width: 0.2))),
            MediaClip(source: text, duration: duration, audio: AudioSettings(pan: 2)),
            MediaClip(source: text, duration: duration, audio: AudioSettings(fadeIn: duration, fadeOut: duration)),
            MediaClip(source: text, duration: duration, effectsOffset: duration),
        ]
        for clip in invalid {
            #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate() }
        }
        #expect(throws: VideoError.self) { try VideoProject(canvas: VideoSize(width: 0, height: 100)).validate() }
        #expect(throws: VideoError.self) { try VideoProject(background: VideoColor(red: .nan, green: 0, blue: 0)).validate() }
    }

    @Test(arguments: [MediaFilter.brightness(2), .contrast(-1), .saturation(.nan), .gaussianBlur(-1), .sepia(2)])
    func invalidFilterParametersAreRejected(_ filter: MediaFilter) throws {
        let clip = MediaClip(source: .text("A", TextStyle()), duration: try time(1), filters: [filter])
        #expect(throws: VideoError.self) { try VideoProject(tracks: [MediaTrack(clips: [clip])]).validate() }
    }

    @Test func androidPlanPreservesOrderTrimmedEnvelopesAndScaledText() async throws {
        let duration = try time(4)
        let audio = MediaClip(source: .audio(URL(fileURLWithPath: "/music.wav")), duration: duration,
                             audio: AudioSettings(volume: 0.5, pan: -1, fadeIn: try time(2)))
        let title = MediaClip(source: .text("Title", TextStyle(fontSize: 120, shadow: TextShadow(radius: 8))),
                              duration: duration, zIndex: 2, filters: [.sepia(0.2), .gaussianBlur(2), .brightness(0.1), .contrast(1.2), .saturation(0)])
        let editor = try VideoEditor(project: VideoProject(tracks: [MediaTrack(clips: [audio, title])]))
        let edited = try await editor.apply([.trim(audio.id, keeping: VideoTimeRange(start: time(1), duration: time(2)))])
        let plan = try AndroidRenderPlan(project: edited, settings: ExportSettings(resolution: VideoSize(width: 960, height: 540)))
        #expect(plan.clips.map(\.id) == [title.id.uuidString, audio.id.uuidString])
        #expect(plan.clips[0].textStyle?.fontSize == 60)
        #expect(plan.clips[0].textStyle?.shadow?.radius == 4)
        #expect(plan.clips[0].filters.map(\.kind) == ["sepia", "blur", "brightness", "contrast", "saturation"])
        let sound = plan.clips[1]
        #expect(sound.sourceStartUs == 1_000_000 && sound.startUs == 1_000_000 && sound.durationUs == 2_000_000)
        #expect(sound.rightGain == 0 && abs(sound.leftGain - sqrt(2)) < 0.0001)
        #expect(sound.envelope.map(\.seconds) == [0, 1, 2])
        #expect(sound.envelope.map(\.gain) == [0.25, 0.5, 0.5])
        #expect(try !JSONEncoder().encode(plan).isEmpty)
    }
}
