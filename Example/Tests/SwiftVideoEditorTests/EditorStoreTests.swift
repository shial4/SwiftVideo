// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import Testing
import SwiftVideo
@testable import SwiftVideoEditor

@Suite @MainActor struct EditorStoreTests {
    func store() throws -> EditorStore {
        let store = EditorStore()
        store.rendersPreviews = false
        store.assets = try DemoAssets.load()
        store.project = try #require(store.assets).project()
        store.selectedID = store.project.tracks[0].clips[0].id
        return store
    }

    @Test func trackAndClipSpeedAndFiltersSupportUndoRedo() async throws {
        let store = try store()
        let original = store.project
        await store.setSpeed(.double)
        #expect(store.selected?.duration == (try seconds(2)))
        store.selectTrack(store.project.tracks[0])
        await store.setSpeed(.half)
        #expect(store.selectedTrack?.clips[0].duration == (try seconds(4)))
        await store.setFilter(.mono)
        #expect(store.selectedTrack?.filters == EditorFilter.mono.effects)
        await store.setAudioFilters([.highPass(cutoffHz: 80)])
        #expect(store.selectedTrack?.audioFilters == [.highPass(cutoffHz: 80)])
        let changed = store.project
        for _ in 0..<4 { store.undo() }
        #expect(store.project == original && store.selectedTrack != nil)
        for _ in 0..<4 { store.redo() }
        #expect(store.project == changed && store.selectedTrack != nil)
        store.select(store.project.tracks[0].clips[0])
        await store.setAudioFilters([.lowPass(cutoffHz: 4_000)])
        await store.setAudio(volume: 0.5, pan: 0, muted: false, fading: false)
        #expect(store.selected?.audio.filters == [.lowPass(cutoffHz: 4_000)])
    }

    @Test func demoAssetsAreReadableAndTimelineIsValid() throws {
        let store = try store()
        try store.project.validate()
        #expect(store.duration == 8)
        for clip in store.project.tracks.flatMap(\.clips) {
            if let url = clip.source.url { #expect(try Data(contentsOf: url).count > 100) }
        }
    }

    @Test func splitUndoRedoAndNewEditKeepConsistentHistory() async throws {
        let store = try store()
        let initial = store.project
        store.playhead = 2
        await store.split()
        let split = store.project
        #expect(split.tracks[0].clips.count == 3)
        store.undo()
        #expect(store.project == initial && store.canRedo)
        store.redo()
        #expect(store.project == split)
        store.undo()
        await store.setFilter(.mono)
        #expect(!store.canRedo)
        #expect(store.selected?.filters == EditorFilter.mono.effects)
    }

    @Test func deletingThenUndoingRestoresValidSelection() async throws {
        let store = try store()
        let before = store.project
        await store.removeSelected()
        #expect(store.selected != nil)
        store.undo()
        #expect(store.project == before && store.selected != nil)
        store.redo()
        #expect(store.selected != nil)
    }

    @Test func failedEditDoesNotCreateUndoEntry() async throws {
        let store = try store()
        let before = store.project
        store.playhead = 0
        await store.split()
        #expect(store.message != nil)
        #expect(store.project == before && !store.canUndo)
    }

    @Test func titleOverlayAudioAndTrimUseLibraryEdits() async throws {
        let store = try store()
        await store.addTitle()
        await store.setText("A new story")
        #expect(store.selected?.source == .text("A new story", TextStyle(fontSize: 120, shadow: TextShadow(radius: 6))))
        let overlays = store.project.tracks[2].clips.count
        await store.addOverlay()
        #expect(store.project.tracks[2].clips.count == overlays + 1)
        store.selectedID = store.project.tracks[3].clips[0].id
        await store.setAudio(volume: 0.25, pan: 1, muted: false, fading: false)
        #expect(store.selected?.audio.volume == 0.25 && store.selected?.audio.pan == 1)
        store.selectedID = store.project.tracks[0].clips[0].id
        await store.trim(start: 1, end: 3)
        #expect(store.selected?.sourceStart == (try seconds(1)))
        #expect(store.selected?.duration == (try seconds(2)))
        try store.project.validate()
    }
}
