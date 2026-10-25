// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftVideo

struct EditorTimeline: View {
    let store: EditorStore
    let pixelsPerSecond = 62.0
    var body: some View {
        VStack(spacing: 5) {
            HStack {
                Text("TIMELINE").font(.system(size: 9, weight: .bold)).tracking(1.2)
                Spacer()
                Text("\(store.project.tracks.flatMap(\.clips).count) clips").font(.system(size: 10))
                Image(systemName: "magnifyingglass").font(.system(size: 11))
            }.foregroundStyle(EditorTheme.muted).padding(.horizontal, 18).padding(.top, 12)
            ScrollView(.horizontal) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 0) {
                        ForEach(0..<(Int(ceil(store.duration)) + 1), id: \.self) { second in
                            Text(second.isMultiple(of: 2) ? "\(second)s" : "|")
                                .font(.system(size: 9, design: .monospaced)).foregroundStyle(EditorTheme.muted)
                                .frame(width: pixelsPerSecond, alignment: .leading)
                        }
                    }.padding(.leading, 18)
                    ZStack(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(store.project.tracks) { track in
                                ZStack(alignment: .leading) {
                                    RoundedRectangle(cornerRadius: 4).fill(.white.opacity(0.025))
                                    ForEach(track.clips) { clip in
                                        Button { store.select(clip) } label: {
                                            TimelineClip(clip: clip, selected: store.selectedID == clip.id)
                                                .frame(width: max(26, clip.duration.seconds * pixelsPerSecond - 3), height: track.name == "Footage" ? 43 : 25)
                                        }.buttonStyle(.plain).offset(x: clip.start.seconds * pixelsPerSecond)
                                            .accessibilityLabel("\(track.name): \(clip.displayName)")
                                    }
                                }.frame(width: max(500, store.duration * pixelsPerSecond), height: track.name == "Footage" ? 43 : 25)
                            }
                        }
                        Rectangle().fill(.white).frame(width: 1.5, height: 135).offset(x: store.playhead * pixelsPerSecond).allowsHitTesting(false)
                    }.padding(.horizontal, 18)
                }
            }
            Slider(value: Binding(get: { store.playhead }, set: { store.seek($0) }), in: 0...max(0.1, store.duration))
                .tint(EditorTheme.accent).padding(.horizontal, 18).accessibilityLabel("Timeline playhead").accessibilityIdentifier("editor.scrub")
        }.background(EditorTheme.background)
    }
}

struct TimelineClip: View {
    let clip: MediaClip
    let selected: Bool
    var color: Color {
        switch clip.source { case .video: Color(red: 0.2, green: 0.4, blue: 0.42)
        case .text: Color(red: 0.42, green: 0.3, blue: 0.65)
        case .image: Color(red: 0.65, green: 0.4, blue: 0.21)
        case .audio: Color(red: 0.14, green: 0.46, blue: 0.4) }
    }
    var body: some View {
        ZStack(alignment: .leading) {
            color
            if case .video = clip.source {
                HStack(spacing: 1) {
                    ForEach(0..<5, id: \.self) { _ in
                        Image("coast", bundle: .module).resizable().scaledToFill().frame(width: 52).clipped()
                    }
                }.opacity(0.65)
            }
            if case .audio = clip.source {
                HStack(alignment: .center, spacing: 2) {
                    ForEach(0..<60, id: \.self) { index in
                        Rectangle().fill(EditorTheme.accent.opacity(0.45)).frame(width: 2, height: 3 + abs(sin(Double(index) * 0.77)) * 17)
                    }
                }.padding(.horizontal, 6)
            }
            Text(clip.displayName).font(.system(size: 9, weight: .medium)).lineLimit(1).padding(.horizontal, 8).shadow(color: .black, radius: 2)
        }.clipShape(RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(selected ? EditorTheme.accent : .white.opacity(0.12), lineWidth: selected ? 2 : 1))
    }
}
