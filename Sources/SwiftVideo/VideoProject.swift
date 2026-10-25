// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum MediaSource: Hashable, Codable, Sendable {
    case video(URL)
    case image(URL)
    case text(String, TextStyle)
    case audio(URL)

    public var isVisual: Bool { if case .audio = self { false } else { true } }
    public var hasAudio: Bool {
        switch self { case .video, .audio: true; case .image, .text: false }
    }
    public var url: URL? {
        switch self { case .video(let url), .image(let url), .audio(let url): url; case .text: nil }
    }
}

public struct AudioSettings: Hashable, Codable, Sendable {
    public let volume: Double
    public let isMuted: Bool
    /// Constant-power stereo pan, -1 (left) through 1 (right).
    public let pan: Double
    public let fadeIn: VideoTime
    public let fadeOut: VideoTime
    public init(volume: Double = 1, isMuted: Bool = false, pan: Double = 0,
                fadeIn: VideoTime = .zero, fadeOut: VideoTime = .zero) {
        self.volume = volume; self.isMuted = isMuted; self.pan = pan
        self.fadeIn = fadeIn; self.fadeOut = fadeOut
    }

    public func gain(at time: VideoTime, duration: VideoTime) -> Double {
        guard !isMuted, time >= .zero, time < duration else { return 0 }
        return gain(atSeconds: time.seconds, durationSeconds: duration.seconds)
    }

    func gain(atSeconds time: Double, durationSeconds duration: Double, includeEnd: Bool = false) -> Double {
        guard !isMuted, time >= 0, includeEnd ? time <= duration : time < duration else { return 0 }
        let start = fadeIn > .zero ? min(1, time / fadeIn.seconds) : 1
        let end = fadeOut > .zero ? min(1, (duration - time) / fadeOut.seconds) : 1
        return volume * max(0, min(start, end))
    }
}

public struct MediaClip: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let source: MediaSource
    public let start: VideoTime
    public let duration: VideoTime
    public let sourceStart: VideoTime
    public let zIndex: Int
    public let transform: VisualTransform
    public let filters: [MediaFilter]
    public let animations: [KeyframeAnimation]
    public let audio: AudioSettings
    /// Splits and trims preserve the original animation and audio envelope clock.
    public let effectsOffset: VideoTime
    public let effectsDuration: VideoTime

    public init(id: UUID = UUID(), source: MediaSource, start: VideoTime = .zero, duration: VideoTime,
                sourceStart: VideoTime = .zero, zIndex: Int = 0, transform: VisualTransform = VisualTransform(),
                filters: [MediaFilter] = [], animations: [KeyframeAnimation] = [], audio: AudioSettings = AudioSettings(),
                effectsOffset: VideoTime = .zero, effectsDuration: VideoTime? = nil) {
        self.id = id; self.source = source; self.start = start; self.duration = duration
        self.sourceStart = sourceStart; self.zIndex = zIndex; self.transform = transform
        self.filters = filters; self.animations = animations; self.audio = audio
        self.effectsOffset = effectsOffset; self.effectsDuration = effectsDuration ?? duration
    }

    public var timeRange: VideoTimeRange { VideoTimeRange(start: start, duration: duration) }

    public func visualTransform(at projectTime: VideoTime) throws -> VisualTransform {
        let time = try projectTime.subtracting(start).adding(effectsOffset)
        var values: [AnimationProperty: Double] = [:]
        for animation in animations { values[animation.property] = animation.value(at: time) }
        return VisualTransform(x: values[.x] ?? transform.x, y: values[.y] ?? transform.y,
                               width: transform.width, height: transform.height, scale: values[.scale] ?? transform.scale,
                               rotation: values[.rotation] ?? transform.rotation, opacity: values[.opacity] ?? transform.opacity,
                               crop: transform.crop, contentMode: transform.contentMode)
    }

    public func audioGain(at projectTime: VideoTime) throws -> Double {
        guard try timeRange.contains(projectTime) else { return 0 }
        return try audio.gain(at: projectTime.subtracting(start).adding(effectsOffset), duration: effectsDuration)
    }

    func replacing(id: UUID? = nil, start: VideoTime? = nil, duration: VideoTime? = nil,
                   sourceStart: VideoTime? = nil, effectsOffset: VideoTime? = nil, source: MediaSource? = nil,
                   zIndex: Int? = nil, transform: VisualTransform? = nil, filters: [MediaFilter]? = nil,
                   animations: [KeyframeAnimation]? = nil, audio: AudioSettings? = nil) -> MediaClip {
        MediaClip(id: id ?? self.id, source: source ?? self.source, start: start ?? self.start, duration: duration ?? self.duration,
                  sourceStart: sourceStart ?? self.sourceStart, zIndex: zIndex ?? self.zIndex, transform: transform ?? self.transform,
                  filters: filters ?? self.filters, animations: animations ?? self.animations, audio: audio ?? self.audio,
                  effectsOffset: effectsOffset ?? self.effectsOffset, effectsDuration: effectsDuration)
    }
}

/// Tracks group clips. Clips may overlap, including within a track.
public struct MediaTrack: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let clips: [MediaClip]
    public init(id: UUID = UUID(), name: String = "", clips: [MediaClip] = []) {
        self.id = id; self.name = name; self.clips = clips
    }
    func replacing(clips: [MediaClip]) -> MediaTrack { MediaTrack(id: id, name: name, clips: clips) }
}

public struct VideoProject: Hashable, Codable, Sendable {
    public let canvas: VideoSize
    public let frameRate: FrameRate
    public let background: VideoColor
    public let tracks: [MediaTrack]

    public init(canvas: VideoSize = .hd1080, frameRate: FrameRate = .fps30,
                background: VideoColor = .black, tracks: [MediaTrack] = []) {
        self.canvas = canvas; self.frameRate = frameRate; self.background = background; self.tracks = tracks
    }

    public var duration: VideoTime {
        get throws { try tracks.flatMap(\.clips).reduce(.zero) { try max($0, $1.timeRange.end) } }
    }

    /// Back to front. Equal z-indices preserve track order, then clip order.
    public func visualClips(at time: VideoTime) throws -> [MediaClip] {
        try tracks.flatMap(\.clips).enumerated()
            .filter { try $0.element.source.isVisual && $0.element.timeRange.contains(time) }
            .sorted { $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex }
            .map(\.element)
    }

    func replacing(tracks: [MediaTrack]) -> VideoProject {
        VideoProject(canvas: canvas, frameRate: frameRate, background: background, tracks: tracks)
    }
}
