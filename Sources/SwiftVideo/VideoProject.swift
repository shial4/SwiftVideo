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
    public let filters: [AudioFilter]
    public init(volume: Double = 1, isMuted: Bool = false, pan: Double = 0,
                fadeIn: VideoTime = .zero, fadeOut: VideoTime = .zero, filters: [AudioFilter] = []) {
        self.volume = volume; self.isMuted = isMuted; self.pan = pan
        self.fadeIn = fadeIn; self.fadeOut = fadeOut; self.filters = filters
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
    public let playbackRate: PlaybackRate
    public let zIndex: Int
    public let transform: VisualTransform
    public let filters: [MediaFilter]
    public let animations: [KeyframeAnimation]
    public let textMotion: TextMotion?
    public let audio: AudioSettings
    /// Splits and trims preserve the original animation and audio envelope clock.
    public let effectsOffset: VideoTime
    public let effectsDuration: VideoTime

    public init(id: UUID = UUID(), source: MediaSource, start: VideoTime = .zero, duration: VideoTime,
                sourceStart: VideoTime = .zero, zIndex: Int = 0, transform: VisualTransform = VisualTransform(),
                filters: [MediaFilter] = [], animations: [KeyframeAnimation] = [], audio: AudioSettings = AudioSettings(),
                effectsOffset: VideoTime = .zero, effectsDuration: VideoTime? = nil, playbackRate: PlaybackRate = .normal,
                textMotion: TextMotion? = nil) {
        self.id = id; self.source = source; self.start = start; self.duration = duration
        self.playbackRate = playbackRate
        self.sourceStart = sourceStart; self.zIndex = zIndex; self.transform = transform
        self.filters = filters; self.animations = animations; self.audio = audio
        self.textMotion = textMotion
        self.effectsOffset = effectsOffset; self.effectsDuration = effectsDuration ?? duration
    }

    public var timeRange: VideoTimeRange { VideoTimeRange(start: start, duration: duration) }

    public func visualTransform(at projectTime: VideoTime) throws -> VisualTransform {
        let time = try projectTime.subtracting(start).adding(effectsOffset)
        return transform.applying(animations, at: time)
    }

    public func audioGain(at projectTime: VideoTime) throws -> Double {
        guard try timeRange.contains(projectTime) else { return 0 }
        return try audio.gain(at: projectTime.subtracting(start).adding(effectsOffset), duration: effectsDuration)
    }

    func replacing(id: UUID? = nil, start: VideoTime? = nil, duration: VideoTime? = nil,
                   sourceStart: VideoTime? = nil, effectsOffset: VideoTime? = nil, source: MediaSource? = nil,
                   zIndex: Int? = nil, transform: VisualTransform? = nil, filters: [MediaFilter]? = nil,
                   animations: [KeyframeAnimation]? = nil, audio: AudioSettings? = nil,
                   effectsDuration: VideoTime? = nil, playbackRate: PlaybackRate? = nil, textMotion: TextMotion?? = nil) -> MediaClip {
        MediaClip(id: id ?? self.id, source: source ?? self.source, start: start ?? self.start, duration: duration ?? self.duration,
                  sourceStart: sourceStart ?? self.sourceStart, zIndex: zIndex ?? self.zIndex, transform: transform ?? self.transform,
                  filters: filters ?? self.filters, animations: animations ?? self.animations, audio: audio ?? self.audio,
                  effectsOffset: effectsOffset ?? self.effectsOffset, effectsDuration: effectsDuration ?? self.effectsDuration,
                  playbackRate: playbackRate ?? self.playbackRate, textMotion: textMotion ?? self.textMotion)
    }
}

/// Tracks group clips. Clips may overlap, including within a track.
public struct MediaTrack: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let name: String
    public let clips: [MediaClip]
    public let playbackRate: PlaybackRate
    public let filters: [MediaFilter]
    public let audioFilters: [AudioFilter]
    public init(id: UUID = UUID(), name: String = "", clips: [MediaClip] = [],
                playbackRate: PlaybackRate = .normal, filters: [MediaFilter] = [], audioFilters: [AudioFilter] = []) {
        self.id = id; self.name = name; self.clips = clips
        self.playbackRate = playbackRate; self.filters = filters; self.audioFilters = audioFilters
    }
    func replacing(clips: [MediaClip]) -> MediaTrack {
        MediaTrack(id: id, name: name, clips: clips, playbackRate: playbackRate, filters: filters, audioFilters: audioFilters)
    }
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

extension AudioSettings {
    private enum CodingKeys: String, CodingKey { case volume, isMuted, pan, fadeIn, fadeOut, filters }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            volume: try values.decode(Double.self, forKey: .volume),
            isMuted: try values.decode(Bool.self, forKey: .isMuted),
            pan: try values.decode(Double.self, forKey: .pan),
            fadeIn: try values.decode(VideoTime.self, forKey: .fadeIn),
            fadeOut: try values.decode(VideoTime.self, forKey: .fadeOut),
            filters: try values.decodeIfPresent([AudioFilter].self, forKey: .filters) ?? [])
    }
}

extension MediaClip {
    private enum CodingKeys: String, CodingKey { case id, source, start, duration, sourceStart, zIndex, transform, filters, animations, audio, effectsOffset, effectsDuration, playbackRate, textMotion }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            source: try values.decode(MediaSource.self, forKey: .source),
            start: try values.decode(VideoTime.self, forKey: .start),
            duration: try values.decode(VideoTime.self, forKey: .duration),
            sourceStart: try values.decode(VideoTime.self, forKey: .sourceStart),
            zIndex: try values.decode(Int.self, forKey: .zIndex),
            transform: try values.decode(VisualTransform.self, forKey: .transform),
            filters: try values.decode([MediaFilter].self, forKey: .filters),
            animations: try values.decode([KeyframeAnimation].self, forKey: .animations),
            audio: try values.decode(AudioSettings.self, forKey: .audio),
            effectsOffset: try values.decode(VideoTime.self, forKey: .effectsOffset),
            effectsDuration: try values.decode(VideoTime.self, forKey: .effectsDuration),
            playbackRate: try values.decodeIfPresent(PlaybackRate.self, forKey: .playbackRate) ?? .normal,
            textMotion: try values.decodeIfPresent(TextMotion.self, forKey: .textMotion))
    }
}

extension MediaTrack {
    private enum CodingKeys: String, CodingKey { case id, name, clips, playbackRate, filters, audioFilters }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            id: try values.decode(UUID.self, forKey: .id),
            name: try values.decode(String.self, forKey: .name),
            clips: try values.decode([MediaClip].self, forKey: .clips),
            playbackRate: try values.decodeIfPresent(PlaybackRate.self, forKey: .playbackRate) ?? .normal,
            filters: try values.decodeIfPresent([MediaFilter].self, forKey: .filters) ?? [],
            audioFilters: try values.decodeIfPresent([AudioFilter].self, forKey: .audioFilters) ?? [])
    }
}
