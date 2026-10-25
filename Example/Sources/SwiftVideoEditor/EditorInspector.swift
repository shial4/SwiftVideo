// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftVideo

struct EditorInspector: View {
    let store: EditorStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text(store.tool.rawValue.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.2)
                    Spacer()
                    if let clip = store.selected { Text(clip.displayName).font(.system(size: 10)).lineLimit(1).foregroundStyle(EditorTheme.muted) }
                }
                switch store.tool {
                case .edit:
                    if let clip = store.selected {
                        ClipInspector(store: store, clip: clip).id(clip.id)
                    }
                case .text:
                    if let clip = store.selected, case .text(let value, _) = clip.source {
                        TitleInspector(store: store, text: value).id(clip.id)
                    } else {
                        Button("Select existing title") {
                            if let clip = store.project.tracks.flatMap(\.clips).first(where: { if case .text = $0.source { true } else { false } }) { store.select(clip) }
                        }.editorSecondaryButton()
                    }
                    Button { Task { await store.addTitle() } } label: { Label("Add text", systemImage: "plus") }
                        .editorSecondaryButton().accessibilityIdentifier("editor.addText")
                case .filters:
                    Text("Give the selected layer a new look.").font(.system(size: 11)).foregroundStyle(EditorTheme.muted)
                    ForEach(EditorFilter.allCases) { filter in
                        Button { Task { await store.setFilter(filter) } } label: {
                            HStack {
                                Circle().fill(filter == .mono ? Color.gray : EditorTheme.accent.opacity(filter == .original ? 0.3 : 0.8)).frame(width: 16, height: 16)
                                Text(filter.rawValue)
                                Spacer()
                                if store.selected?.filters == filter.effects { Image(systemName: "checkmark").foregroundStyle(EditorTheme.accent) }
                            }.padding(10).background(EditorTheme.raised, in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain).font(.system(size: 12)).accessibilityIdentifier("editor.filter.\(filter.rawValue.lowercased())")
                    }
                case .audio:
                    if let music = store.project.tracks.flatMap(\.clips).first(where: { if case .audio = $0.source { true } else { false } }), store.selectedID != music.id {
                        Button("Select soundtrack") { store.select(music) }.editorSecondaryButton()
                    }
                    if let clip = store.selected, clip.source.hasAudio { AudioInspector(store: store, clip: clip).id(clip.id) }
                    else { Text("Select a video or audio clip.").font(.system(size: 12)).foregroundStyle(EditorTheme.muted) }
                case .overlay:
                    Text("Layer an image over your footage. Scale, rotate, and fade it with the Edit tools.")
                        .font(.system(size: 12)).foregroundStyle(EditorTheme.muted)
                    Button { Task { await store.addOverlay() } } label: { Label("Add image overlay", systemImage: "plus") }
                        .editorSecondaryButton().accessibilityIdentifier("editor.addOverlay")
                    Button { Task { await store.appendFootage() } } label: { Label { Text("Add another video") } icon: { EditorIcon("film") } }
                        .editorSecondaryButton()
                }
            }.padding(18)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ClipInspector: View {
    let store: EditorStore
    let clip: MediaClip
    @State var scale = 1.0
    @State var rotation = 0.0
    @State var opacity = 1.0
    @State var trimStart = 0.0
    @State var trimEnd = 1.0
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Button { Task { await store.split() } } label: { Label { Text("Split") } icon: { EditorIcon("scissors") } }
                    .editorSecondaryButton()
                    .accessibilityIdentifier("editor.split")
                    .disabled(store.playhead <= clip.start.seconds || store.playhead >= clip.start.seconds + clip.duration.seconds)
                Button(role: .destructive) { Task { await store.removeSelected() } } label: { Image(systemName: "trash") }
                    .editorSecondaryButton()
                    .accessibilityLabel("Delete selected clip").accessibilityIdentifier("editor.delete")
            }
            if clip.source.isVisual {
                InspectorSlider(title: "Scale", value: $scale, range: 0.5...2, format: "%.2fx", commit: applyTransform)
                InspectorSlider(title: "Rotation", value: $rotation, range: -180...180, format: "%.0f", commit: applyTransform)
                InspectorSlider(title: "Opacity", value: $opacity, range: 0...1, format: "%.2f", commit: applyTransform)
            }
            Divider().overlay(.white.opacity(0.08))
            Text("TRIM RANGE").font(.system(size: 9, weight: .bold)).foregroundStyle(EditorTheme.muted)
            InspectorSlider(title: "In", value: $trimStart, range: 0...max(0.01, clip.duration.seconds - 0.1), format: "%.1fs", commit: {})
            InspectorSlider(title: "Out", value: $trimEnd, range: 0.1...max(0.1, clip.duration.seconds), format: "%.1fs", commit: {})
            Button("Apply trim") { Task { await store.trim(start: trimStart, end: trimEnd) } }
                .disabled(trimEnd <= trimStart).editorSecondaryButton().accessibilityIdentifier("editor.trim")
        }.onAppear {
            scale = clip.transform.scale; rotation = clip.transform.rotation; opacity = clip.transform.opacity
            trimEnd = clip.duration.seconds
        }
    }
    func applyTransform() { Task { await store.setTransform(scale: scale, rotation: rotation, opacity: opacity) } }
}

struct InspectorSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let commit: () -> Void
    var body: some View {
        VStack(spacing: 3) {
            HStack {
                Text(title).font(.system(size: 11))
                Spacer()
                Text(String(format: format, value)).font(.system(size: 10, design: .monospaced)).foregroundStyle(EditorTheme.muted)
            }
            Slider(value: $value, in: range, onEditingChanged: { active in if !active { commit() } })
                .tint(EditorTheme.accent).accessibilityLabel(Text(title))
        }
    }
}

struct TitleInspector: View {
    let store: EditorStore
    let text: String
    @State var draft = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Your title", text: $draft).textFieldStyle(.roundedBorder).accessibilityIdentifier("editor.titleText")
            Button("Apply title") { Task { await store.setText(draft) } }
                .editorSecondaryButton().accessibilityIdentifier("editor.applyTitle")
            Text("The opening title includes a fade and vertical keyframe animation.")
                .font(.system(size: 11)).foregroundStyle(EditorTheme.muted)
        }.onAppear { draft = text }
    }
}

struct AudioInspector: View {
    let store: EditorStore
    let clip: MediaClip
    @State var volume = 0.6
    @State var pan = 0.0
    @State var muted = false
    @State var fading = true
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InspectorSlider(title: "Volume", value: $volume, range: 0...1.5, format: "%.2f", commit: apply)
            InspectorSlider(title: "Pan", value: $pan, range: -1...1, format: "%.2f", commit: apply)
            Toggle("Mute", isOn: Binding(get: { muted }, set: { muted = $0; apply() }))
            Toggle("Fade in / out", isOn: Binding(get: { fading }, set: { fading = $0; apply() }))
        }.font(.system(size: 12)).tint(EditorTheme.accent).onAppear {
            volume = clip.audio.volume; pan = clip.audio.pan; muted = clip.audio.isMuted
            fading = clip.audio.fadeIn > .zero || clip.audio.fadeOut > .zero
        }
    }
    func apply() { Task { await store.setAudio(volume: volume, pan: pan, muted: muted, fading: fading) } }
}

struct ExportSheet: View {
    let store: EditorStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Ready for the world").font(.title2.bold())
                    Text("Export your composition as an MP4.").font(.subheadline).foregroundStyle(EditorTheme.muted)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Close export")
            }
            Picker("Resolution", selection: Binding(get: { store.outputHeight }, set: { store.outputHeight = $0 })) {
                Text("720p").tag(720)
                Text("1080p").tag(1080)
            }.pickerStyle(.segmented).disabled(store.isExporting)
            HStack { Text("H.264 + AAC"); Spacer(); Text("30 fps  /  16:9") }.font(.caption).foregroundStyle(EditorTheme.muted)
            if let progress = store.exportProgress {
                ProgressView(value: progress).tint(EditorTheme.accent)
                Text("Exporting \(Int(progress * 100))%").font(.system(size: 13, design: .monospaced))
                Button("Cancel export") { store.cancelExport() }.editorSecondaryButton()
            } else if let url = store.exportURL {
                Label("Your video is ready", systemImage: "checkmark.circle.fill").foregroundStyle(EditorTheme.accent)
                ShareLink(item: url) { Label("Save or share video", systemImage: "square.and.arrow.up") }
                    .editorSecondaryButton().accessibilityIdentifier("editor.share")
                Text(url.lastPathComponent).font(.caption).foregroundStyle(EditorTheme.muted)
            } else {
                Button { store.export() } label: {
                    Text("Export video").font(.headline).foregroundStyle(.black).frame(maxWidth: .infinity).padding(14)
                        .background(EditorTheme.accent, in: RoundedRectangle(cornerRadius: 10))
                }.buttonStyle(.plain).accessibilityIdentifier("editor.startExport")
            }
            Spacer(minLength: 0)
        }.padding(24).frame(minWidth: 300, idealWidth: 440, minHeight: 330)
            .background(EditorTheme.panel).foregroundStyle(.white).preferredColorScheme(.dark)
    }
}
