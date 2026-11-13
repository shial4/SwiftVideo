// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension AudioSettings {
    public func filter(_ filter: AudioFilter) -> AudioSettings { self.filters(filters + [filter]) }
    public func filters(_ filters: [AudioFilter]) -> AudioSettings {
        AudioSettings(volume: volume, isMuted: isMuted, pan: pan, fadeIn: fadeIn, fadeOut: fadeOut, filters: filters)
    }
}

extension MediaClip {
    /// Keeps the selected source interval and start; retimes duration, animations, and fades.
    /// Stored times always remain project times, including inside a retimed track.
    public func speed(_ rate: PlaybackRate) throws -> MediaClip {
        try retimed(from: playbackRate, to: rate).replacing(playbackRate: rate)
    }

    func retimed(from old: PlaybackRate, to new: PlaybackRate) throws -> MediaClip {
        func scale(_ time: VideoTime) throws -> VideoTime {
            try time.scaled(numerator: Int64(old.numerator) * Int64(new.denominator),
                            denominator: Int64(old.denominator) * Int64(new.numerator))
        }
        let animations = try animations.map { try $0.retimed(scale) }
        let audio = try AudioSettings(volume: audio.volume, isMuted: audio.isMuted, pan: audio.pan,
                                      fadeIn: scale(audio.fadeIn), fadeOut: scale(audio.fadeOut), filters: audio.filters)
        return try replacing(duration: scale(duration), effectsOffset: scale(effectsOffset),
                             animations: animations, audio: audio, effectsDuration: scale(effectsDuration),
                             textMotion: .some(textMotion?.retimed(scale)))
    }

    /// Uses a resolved (clip times track) rate when called by a renderer.
    var sourceDuration: VideoTime { get throws { try duration.scaled(by: playbackRate) } }

    func sourceTime(at projectTime: VideoTime) throws -> VideoTime {
        try projectTime.subtracting(start).scaled(by: playbackRate).adding(sourceStart)
    }
}

extension MediaTrack {
    /// Retimes clips and gaps around the earliest clip start. Other tracks are unaffected.
    public func speed(_ rate: PlaybackRate) throws -> MediaTrack {
        let anchor = clips.map(\.start).min() ?? .zero
        let clips = try clips.map { clip in
            _ = try clip.playbackRate.combined(with: rate)
            let offset = try clip.start.subtracting(anchor).scaled(
                numerator: Int64(playbackRate.numerator) * Int64(rate.denominator),
                denominator: Int64(playbackRate.denominator) * Int64(rate.numerator))
            return try clip.retimed(from: playbackRate, to: rate).replacing(start: anchor.adding(offset))
        }
        return MediaTrack(id: id, name: name, clips: clips, playbackRate: rate, filters: filters, audioFilters: audioFilters)
    }

    /// Track filters follow each visual clip's filters; they do not filter the composited group.
    public func filter(_ filter: MediaFilter) -> MediaTrack { self.filters(filters + [filter]) }
    public func filters(_ filters: [MediaFilter]) -> MediaTrack {
        MediaTrack(id: id, name: name, clips: clips, playbackRate: playbackRate, filters: filters, audioFilters: audioFilters)
    }
    public func audioFilter(_ filter: AudioFilter) -> MediaTrack { self.audioFilters(audioFilters + [filter]) }
    public func audioFilters(_ filters: [AudioFilter]) -> MediaTrack {
        MediaTrack(id: id, name: name, clips: clips, playbackRate: playbackRate, filters: self.filters, audioFilters: filters)
    }
}

extension VideoProject {
    /// The single rendering boundary for inherited per-clip effects. Never persist these copies.
    func renderClips() throws -> [MediaClip] {
        try tracks.flatMap { track in
            try track.clips.map { clip in
                try clip.replacing(filters: clip.filters + (clip.source.isVisual ? track.filters : []),
                                   audio: clip.audio.filters(clip.audio.filters + (clip.source.hasAudio ? track.audioFilters : [])),
                                   playbackRate: clip.playbackRate.combined(with: track.playbackRate))
            }
        }
    }
}
