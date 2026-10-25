// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Observation
import SwiftUI
import SwiftVideo
#if os(Android)
import SkipAV
#else
import AVKit
#endif

@MainActor @Observable
final class EditorStore {
    var project = VideoProject()
    var selectedID: UUID?
    var tool = EditorTool.edit
    var playhead = 0.0
    var isPlaying = false
    var isEditing = false
    var isPreparingPreview = false
    var exportProgress: Double?
    var exportURL: URL?
    var message: String?
    var player = AVPlayer()
    var previewURL: URL?
    var outputHeight = 1080
    var undoHistory: [VideoProject] = []
    var redoHistory: [VideoProject] = []
    var assets: DemoAssets?
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var exportTask: Task<Void, Never>?
    @ObservationIgnored private var playbackTask: Task<Void, Never>?
    @ObservationIgnored private var previewRevision = UUID()
    @ObservationIgnored private var exportRevision: UUID?
    @ObservationIgnored var rendersPreviews = true

    var duration: Double { (try? project.duration.seconds) ?? 0 }
    var selected: MediaClip? { project.tracks.flatMap(\.clips).first { $0.id == selectedID } }
    var canUndo: Bool { !undoHistory.isEmpty && !isEditing }
    var canRedo: Bool { !redoHistory.isEmpty && !isEditing }
    var isExporting: Bool { exportProgress != nil }

    func load() async {
        guard assets == nil else { return }
        do {
            let assets = try DemoAssets.load()
            self.assets = assets
            project = try assets.project()
            selectedID = project.tracks.first?.clips.first?.id
            schedulePreview(delay: false)
        } catch { message = error.localizedDescription }
    }

    func commit(_ edits: [VideoEdit]) async {
        guard !isEditing else { return }
        isEditing = true
        defer { isEditing = false }
        do {
            let before = project
            let editor = try VideoEditor(project: before)
            let after = try await editor.apply(edits)
            guard before != after else { return }
            undoHistory.append(before)
            if undoHistory.count > 50 { undoHistory.removeFirst() }
            redoHistory.removeAll()
            project = after
            playhead = min(playhead, duration)
            if selected == nil { selectedID = project.tracks.flatMap(\.clips).first?.id }
            schedulePreview()
        } catch { message = error.localizedDescription }
    }

    func undo() {
        guard !isEditing, let previous = undoHistory.popLast() else { return }
        redoHistory.append(project); project = previous
        restoreSelection(); schedulePreview()
    }

    func redo() {
        guard !isEditing, let next = redoHistory.popLast() else { return }
        undoHistory.append(project); project = next
        restoreSelection(); schedulePreview()
    }

    private func restoreSelection() {
        playhead = min(playhead, duration)
        if selected == nil { selectedID = project.tracks.flatMap(\.clips).first?.id }
    }

    func select(_ clip: MediaClip) {
        selectedID = clip.id
        seek(max(clip.start.seconds, min(playhead, clip.start.seconds + clip.duration.seconds - 0.01)))
        switch clip.source { case .text: tool = .text; case .audio: tool = .audio; default: tool = .edit }
    }

    func split() async {
        guard let clip = selected else { return }
        do { await commit([.split(clip.id, at: try seconds(playhead), rightID: UUID())]) }
        catch { message = error.localizedDescription }
    }

    func trim(start: Double, end: Double) async {
        guard let clip = selected else { return }
        do { await commit([.trim(clip.id, keeping: VideoTimeRange(start: try seconds(start), duration: try seconds(end - start)))]) }
        catch { message = error.localizedDescription }
    }

    func removeSelected() async {
        guard let selectedID else { return }
        await commit([.removeClip(selectedID)])
    }

    func setFilter(_ filter: EditorFilter) async {
        guard let clip = selected, clip.source.isVisual else { return }
        await commit([.replaceClip(clip.filters(filter.effects))])
    }

    func setText(_ text: String) async {
        guard let clip = selected, case .text(_, let style) = clip.source, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        await commit([.replaceClip(clip.source(.text(text, style)))])
    }

    func setAudio(volume: Double, pan: Double, muted: Bool, fading: Bool) async {
        guard let clip = selected else { return }
        do {
            let fade = try seconds(fading ? min(0.5, clip.effectsDuration.seconds / 2) : 0)
            await commit([.replaceClip(clip.audio(AudioSettings(volume: volume, isMuted: muted, pan: pan, fadeIn: fade, fadeOut: fade)))])
        } catch { message = error.localizedDescription }
    }

    func setTransform(scale: Double, rotation: Double, opacity: Double) async {
        guard let clip = selected else { return }
        let t = clip.transform
        let value = VisualTransform(x: t.x, y: t.y, width: t.width, height: t.height, scale: scale,
            rotation: rotation, opacity: opacity, crop: t.crop, contentMode: t.contentMode)
        await commit([.replaceClip(clip.transform(value))])
    }

    func addTitle() async {
        guard let track = project.tracks.first(where: { $0.name == "Titles" }) else { return }
        do {
            let length = max(0.5, min(3, duration - playhead))
            let clip = MediaClip(source: .text("YOUR STORY", TextStyle(fontSize: 120, shadow: TextShadow(radius: 6))),
                start: try seconds(playhead), duration: try seconds(length), zIndex: 10,
                transform: VisualTransform(y: 0.5, width: 0.9, height: 0.3))
            await commit([.addClip(clip, trackID: track.id)]); selectedID = clip.id; tool = .text
        } catch { message = error.localizedDescription }
    }

    func addOverlay() async {
        guard let assets, let track = project.tracks.first(where: { $0.name == "Overlays" }) else { return }
        do {
            let clip = MediaClip(source: .image(assets.coast), start: try seconds(playhead),
                duration: try seconds(max(0.5, min(3, duration - playhead))), zIndex: 5,
                transform: VisualTransform(x: 0.8, y: 0.25, width: 0.3, height: 0.3, contentMode: .fill))
            await commit([.addClip(clip, trackID: track.id)]); selectedID = clip.id; tool = .edit
        } catch { message = error.localizedDescription }
    }

    func appendFootage() async {
        guard let assets, let track = project.tracks.first else { return }
        do {
            let clip = MediaClip(source: .video(assets.close), duration: try seconds(4), audio: AudioSettings(isMuted: true))
            let start = try track.clips.reduce(VideoTime.zero) { try max($0, $1.timeRange.end) }
            await commit([.mergeSequentially([clip], trackID: track.id, start: start)]); selectedID = clip.id
        } catch { message = error.localizedDescription }
    }

    func seek(_ time: Double) {
        playhead = min(max(0, time), max(0, duration - 0.001))
        player.seek(to: CMTime(seconds: playhead, preferredTimescale: 600))
    }

    func togglePlayback() {
        if isPlaying { pause(); return }
        guard previewURL != nil else { return }
        if playhead >= duration - 0.1 { seek(0) }
        isPlaying = true
        player.play()
        playbackTask?.cancel()
        playbackTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                guard !Task.isCancelled, let self else { break }
                let current = player.currentTime().seconds
                if current.isFinite { playhead = min(duration, max(0, current)) }
                if playhead >= duration - 0.05 { pause(); break }
            }
        }
    }

    func pause() { isPlaying = false; player.pause(); playbackTask?.cancel(); playbackTask = nil }

    func schedulePreview(delay: Bool = true) {
        previewTask?.cancel(); pause()
        guard rendersPreviews else { return }
        let revision = UUID(); previewRevision = revision
        let snapshot = project
        isPreparingPreview = true
        previewTask = Task { [weak self] in
            guard let self else { return }
            let output = FileManager.default.temporaryDirectory.appendingPathComponent("preview-\(revision).mp4")
            do {
                if delay { try await Task.sleep(for: .milliseconds(450)) }
                try await VideoExporter().export(snapshot, to: output,
                    settings: ExportSettings(resolution: VideoSize(width: 640, height: 360), frameRate: .fps30, videoBitRate: 1_000_000))
                try Task.checkCancellation()
                guard revision == previewRevision else { try? FileManager.default.removeItem(at: output); return }
                let old = previewURL
                player.replaceCurrentItem(with: AVPlayerItem(url: output))
                previewURL = output; seek(playhead); isPreparingPreview = false
                if let old { try? FileManager.default.removeItem(at: old) }
            } catch {
                try? FileManager.default.removeItem(at: output)
                guard revision == previewRevision else { return }
                isPreparingPreview = false
                if !Task.isCancelled { message = error.localizedDescription }
            }
        }
    }

    func export() {
        guard !isExporting else { return }
        pause(); exportProgress = 0; exportURL = nil
        let revision = UUID(); exportRevision = revision
        let snapshot = project
        let height = outputHeight
        exportTask = Task { [weak self] in
            guard let self else { return }
            do {
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                    ?? FileManager.default.temporaryDirectory
                try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
                let output = documents.appendingPathComponent("SwiftVideo-\(UUID().uuidString.prefix(8)).mp4")
                try await VideoExporter().export(snapshot, to: output,
                    settings: ExportSettings(resolution: VideoSize(width: height * 16 / 9, height: height))) { [weak self] event in
                        Task { @MainActor in
                            guard let self, self.exportRevision == revision else { return }
                            self.exportProgress = event.fraction
                        }
                    }
                exportURL = output
            } catch { if !Task.isCancelled { message = error.localizedDescription } }
            exportRevision = nil; exportProgress = nil; exportTask = nil
        }
    }

    func cancelExport() { exportTask?.cancel() }
}
