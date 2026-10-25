// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

public enum VideoEdit: Sendable {
    case addTrack(MediaTrack)
    case removeTrack(UUID)
    case addClip(MediaClip, trackID: UUID)
    case replaceClip(MediaClip)
    case removeClip(UUID)
    /// Split at absolute project time. The left clip retains its ID.
    case split(UUID, at: VideoTime, rightID: UUID)
    /// Retain a range relative to the existing clip's beginning; no ripple editing.
    case trim(UUID, keeping: VideoTimeRange)
    case offset(UUID, by: VideoTime)
    /// Place clips consecutively, retaining their individual effects and source trims.
    case mergeSequentially([MediaClip], trackID: UUID, start: VideoTime)
}

/// Owns editing state. Each batch either commits a fully valid snapshot or changes nothing.
public actor VideoEditor {
    private var project: VideoProject

    public init(project: VideoProject = VideoProject()) throws {
        try project.validate()
        self.project = project
    }

    public func snapshot() -> VideoProject { project }

    @discardableResult
    public func apply(_ edits: [VideoEdit]) throws -> VideoProject {
        var tracks = project.tracks
        for edit in edits {
            switch edit {
            case .addTrack(let track): tracks.append(track)
            case .removeTrack(let id):
                let index = try trackIndex(id, in: tracks)
                tracks.remove(at: index)
            case .addClip(let clip, let id):
                let index = try trackIndex(id, in: tracks)
                tracks[index] = tracks[index].replacing(clips: tracks[index].clips + [clip])
            case .mergeSequentially(let clips, let id, let start):
                let index = try trackIndex(id, in: tracks)
                var cursor = start
                var merged = tracks[index].clips
                for clip in clips {
                    merged.append(clip.replacing(start: cursor))
                    cursor = try cursor.adding(clip.duration)
                }
                tracks[index] = tracks[index].replacing(clips: merged)
            case .replaceClip(let replacement):
                try updateClip(replacement.id, tracks: &tracks) { _ in [replacement] }
            case .removeClip(let id): try updateClip(id, tracks: &tracks) { _ in [] }
            case .offset(let id, let offset):
                try updateClip(id, tracks: &tracks) { clip in [try clip.replacing(start: clip.start.adding(offset))] }
            case .split(let id, let time, let rightID):
                try updateClip(id, tracks: &tracks) { clip in
                    let leftDuration = try time.subtracting(clip.start)
                    guard leftDuration > .zero && leftDuration < clip.duration else {
                        throw VideoError.invalidProject("A split must be strictly inside the clip.")
                    }
                    return [clip.replacing(duration: leftDuration),
                            try clip.replacing(id: rightID, start: time, duration: clip.duration.subtracting(leftDuration),
                                               sourceStart: clip.sourceStart.adding(leftDuration),
                                               effectsOffset: clip.effectsOffset.adding(leftDuration))]
                }
            case .trim(let id, let range):
                try updateClip(id, tracks: &tracks) { clip in
                    guard range.start >= .zero, range.duration > .zero, try range.end <= clip.duration else {
                        throw VideoError.invalidProject("Trim range must be nonempty and inside the clip.")
                    }
                    return [try clip.replacing(start: clip.start.adding(range.start), duration: range.duration,
                                               sourceStart: clip.sourceStart.adding(range.start),
                                               effectsOffset: clip.effectsOffset.adding(range.start))]
                }
            }
        }
        let candidate = project.replacing(tracks: tracks)
        try candidate.validate()
        project = candidate
        return candidate
    }

    private func trackIndex(_ id: UUID, in tracks: [MediaTrack]) throws -> Int {
        guard let index = tracks.firstIndex(where: { $0.id == id }) else { throw VideoError.missingTrack(id) }
        return index
    }

    private func updateClip(_ id: UUID, tracks: inout [MediaTrack], change: (MediaClip) throws -> [MediaClip]) throws {
        for index in tracks.indices {
            if let clipIndex = tracks[index].clips.firstIndex(where: { $0.id == id }) {
                var clips = tracks[index].clips
                let replacement = try change(clips[clipIndex])
                clips.replaceSubrange(clipIndex...clipIndex, with: replacement)
                tracks[index] = tracks[index].replacing(clips: clips)
                return
            }
        }
        throw VideoError.missingClip(id)
    }
}
