// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftVideo
#if os(Android)
import SkipAV
#else
import AVKit
#endif

enum EditorTheme {
    static let background = Color(red: 0.045, green: 0.045, blue: 0.055)
    static let panel = Color(red: 0.085, green: 0.085, blue: 0.105)
    static let raised = Color(red: 0.13, green: 0.13, blue: 0.155)
    static let accent = Color(red: 0.35, green: 0.92, blue: 0.81)
    static let muted = Color(red: 0.57, green: 0.58, blue: 0.63)
}

struct ContentView: View {
    @State var store = EditorStore()
    @State var showingExport = false

    var body: some View {
        GeometryReader { geometry in
            let wide = geometry.size.width >= 900
            VStack(spacing: 0) {
                EditorHeader(store: store, showingExport: $showingExport)
                Divider().overlay(.white.opacity(0.07))
                if wide {
                    HStack(spacing: 0) {
                        MediaLibrary(store: store).frame(width: 210)
                        VStack(spacing: 0) {
                            PreviewCanvas(store: store).padding(24)
                            PlaybackBar(store: store)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        EditorInspector(store: store).frame(width: 270).background(EditorTheme.panel)
                    }
                } else {
                    PreviewCanvas(store: store).padding(.horizontal, 16).padding(.top, 14)
                        .frame(maxHeight: max(175, geometry.size.height * 0.31))
                    PlaybackBar(store: store)
                }
                EditorTimeline(store: store).frame(height: wide ? 230 : 220)
                EditorTools(store: store)
                if !wide {
                    EditorInspector(store: store).frame(maxHeight: .infinity).background(EditorTheme.panel)
                }
            }
            .background(EditorTheme.background).foregroundStyle(.white).preferredColorScheme(.dark)
            .task { await store.load() }
            .sheet(isPresented: $showingExport) { ExportSheet(store: store) }
            .alert("Unable to complete action", isPresented: Binding(get: { store.message != nil }, set: { if !$0 { store.message = nil } })) {
                Button("OK") { store.message = nil }
            } message: { Text(store.message ?? "") }
        }
    }
}

struct EditorHeader: View {
    let store: EditorStore
    @Binding var showingExport: Bool
    var body: some View {
        HStack(spacing: 12) {
            EditorIcon("film").font(.title3.weight(.semibold)).foregroundStyle(EditorTheme.accent)
            VStack(alignment: .leading, spacing: 3) {
                Text("Coastal escape").font(.system(size: 15, weight: .semibold))
                Text("SWIFTVIDEO STUDIO").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(EditorTheme.muted)
            }
            Spacer()
            Button { store.undo() } label: { EditorIcon("arrow.uturn.backward") }
                .disabled(!store.canUndo).accessibilityLabel("Undo edit").accessibilityIdentifier("editor.undo")
            Button { store.redo() } label: { EditorIcon("arrow.uturn.forward") }
                .disabled(!store.canRedo).accessibilityLabel("Redo edit").accessibilityIdentifier("editor.redo")
            Button { showingExport = true } label: {
                HStack(spacing: 7) { Text("Export"); EditorIcon("arrow.up.right") }
                    .font(.system(size: 13, weight: .bold)).padding(.horizontal, 15).padding(.vertical, 10)
                    .foregroundStyle(.black).background(EditorTheme.accent, in: RoundedRectangle(cornerRadius: 8))
            }.accessibilityIdentifier("editor.export")
        }.buttonStyle(.plain).padding(.horizontal, 18).padding(.vertical, 13).background(EditorTheme.panel)
    }
}

struct PreviewCanvas: View {
    let store: EditorStore
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.black
            if store.previewURL != nil { VideoPlayer(player: store.player).disabled(true) }
            else { Image("coast", bundle: .module).resizable().scaledToFill() }
            HStack(spacing: 5) {
                Circle().fill(store.isPreparingPreview ? Color.orange : EditorTheme.accent).frame(width: 5, height: 5)
                Text(store.isPreparingPreview ? "Updating preview" : "Preview").font(.system(size: 10, weight: .medium))
            }.padding(.horizontal, 9).padding(.vertical, 6).background(.black.opacity(0.6), in: Capsule()).padding(10)
        }.aspectRatio(16 / 9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.white.opacity(0.08)))
            .accessibilityLabel("Composition preview")
    }
}

struct PlaybackBar: View {
    let store: EditorStore
    var body: some View {
        HStack(spacing: 18) {
            HStack(spacing: 0) {
                Text(timecode(store.playhead)).foregroundStyle(.white)
                Text(" / \(timecode(store.duration))").foregroundStyle(EditorTheme.muted)
            }
            Spacer()
            Button { store.seek(max(0, store.playhead - 1)) } label: { EditorIcon("backward.end.fill") }
                .accessibilityLabel("Back one second")
            Button { store.togglePlayback() } label: {
                EditorIcon(store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 18)).frame(width: 32, height: 32)
            }.disabled(store.previewURL == nil).accessibilityLabel(store.isPlaying ? "Pause" : "Play").accessibilityIdentifier("editor.play")
            Button { store.seek(min(store.duration, store.playhead + 1)) } label: { EditorIcon("forward.end.fill") }
                .accessibilityLabel("Forward one second")
            Spacer()
            Text("16:9").font(.system(size: 11, weight: .semibold)).padding(6).background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 5))
        }.font(.system(size: 11, design: .monospaced)).buttonStyle(.plain).padding(.horizontal, 22).padding(.vertical, 12)
    }
    func timecode(_ time: Double) -> String {
        let whole = Int(max(0, time))
        return String(format: "%02d:%02d.%01d", whole / 60, whole % 60, Int(time * 10) % 10)
    }
}

struct MediaLibrary: View {
    let store: EditorStore
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("YOUR MEDIA").font(.system(size: 10, weight: .bold)).tracking(1.3).foregroundStyle(EditorTheme.muted)
            Image("coast", bundle: .module).resizable().scaledToFill().frame(height: 90).clipped().clipShape(RoundedRectangle(cornerRadius: 8))
            Text("Golden hour").font(.system(size: 13, weight: .semibold))
            Text("2 clips  /  1280 x 720").font(.system(size: 10)).foregroundStyle(EditorTheme.muted)
            Button { Task { await store.appendFootage() } } label: { Label("Add footage", systemImage: "plus") }
                .editorSecondaryButton().accessibilityIdentifier("editor.addFootage")
            Divider().overlay(.white.opacity(0.08))
            Label { Text("Ambient soundtrack") } icon: { EditorIcon("music.note") }.font(.system(size: 12))
            Text("Original audio, 8 seconds").font(.system(size: 10)).foregroundStyle(EditorTheme.muted)
            Spacer()
            Text("Built entirely in Swift").font(.system(size: 10)).foregroundStyle(EditorTheme.muted)
        }.padding(18).frame(maxHeight: .infinity).background(EditorTheme.panel)
    }
}

struct EditorTools: View {
    let store: EditorStore
    var body: some View {
        HStack(spacing: 0) {
            ForEach(EditorTool.allCases) { tool in
                Button { store.tool = tool } label: {
                    VStack(spacing: 5) {
                        EditorIcon(tool.symbol).font(.system(size: 17, weight: .medium))
                        Text(tool.rawValue).font(.system(size: 10, weight: .medium))
                    }.frame(maxWidth: .infinity).padding(.vertical, 12)
                        .foregroundStyle(store.tool == tool ? EditorTheme.accent : .white.opacity(0.7))
                }.accessibilityIdentifier("editor.tool.\(tool.rawValue.lowercased())")
            }
        }.buttonStyle(.plain).background(EditorTheme.panel)
    }
}

extension View {
    func editorSecondaryButton() -> some View {
        buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).padding(.horizontal, 12).padding(.vertical, 10)
            .frame(maxWidth: .infinity).background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 7))
    }
}
