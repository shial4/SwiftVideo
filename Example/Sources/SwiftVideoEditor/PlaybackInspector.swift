// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import SwiftUI
import SwiftVideo

struct SpeedInspector: View {
    let store: EditorStore
    private let rates: [PlaybackRate] = [.quarter, .half, .normal, .double, .quadruple]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.selectedTrack == nil ? "CLIP SPEED" : "TRACK SPEED").font(.system(size: 9, weight: .bold))
            HStack(spacing: 4) {
                ForEach(rates, id: \.self) { rate in
                    Button { Task { await store.setSpeed(rate) } } label: {
                        Text(String(format: "%.2gx", rate.multiplier))
                            .font(.system(size: 11)).padding(.vertical, 8).frame(maxWidth: .infinity)
                            .background(store.selectedRate == rate ? EditorTheme.accent.opacity(0.25) : EditorTheme.raised,
                                        in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).disabled(store.isEditing)
                        .accessibilityLabel("Playback speed \(rate.multiplier) times")
                }
            }
            Text("Pitch is preserved. Combined clip and track speed: 0.25x to 4x.")
                .font(.system(size: 11)).foregroundStyle(EditorTheme.muted)
        }
    }
}

struct AudioFilterInspector: View {
    let store: EditorStore
    // Internal state is required by the Skip Fuse view bridge.
    @State var frequency = 1_000.0
    @State var gain = 0.0
    @State var bandwidth = 1.0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.selectedTrack == nil ? "CLIP EQ" : "TRACK EQ").font(.system(size: 9, weight: .bold))
            Text("Filters run from top to bottom, then track filters, before volume and mixing.")
                .font(.system(size: 11)).foregroundStyle(EditorTheme.muted)
            ForEach(Array(store.selectedAudioFilters.enumerated()), id: \.offset) { index, filter in
                HStack {
                    Text(label(filter)).font(.system(size: 11))
                    Spacer()
                    Button {
                        var filters = store.selectedAudioFilters
                        filters.remove(at: index)
                        Task { await store.setAudioFilters(filters) }
                    } label: { Image(systemName: "minus.circle") }
                        .accessibilityLabel("Remove \(label(filter))")
                }
            }
            InspectorSlider(title: "Frequency", value: $frequency, range: 40...12_000, format: "%.0f Hz", commit: {})
            HStack {
                Button("Low pass") { append(.lowPass(cutoffHz: frequency)) }.editorSecondaryButton()
                Button("High pass") { append(.highPass(cutoffHz: frequency)) }.editorSecondaryButton()
            }
            InspectorSlider(title: "EQ gain", value: $gain, range: -24...24, format: "%.1f dB", commit: {})
            InspectorSlider(title: "Bandwidth", value: $bandwidth, range: 0.05...5, format: "%.2f oct", commit: {})
            Button("Add EQ band") { append(.parametricEQ(frequencyHz: frequency, gainDB: gain, bandwidthOctaves: bandwidth)) }
                .editorSecondaryButton()
            if !store.selectedAudioFilters.isEmpty {
                Button("Clear EQ") { Task { await store.setAudioFilters([]) } }.editorSecondaryButton()
            }
        }.disabled(store.isEditing)
    }

    private func append(_ filter: AudioFilter) {
        let filters = store.selectedAudioFilters + [filter]
        Task { await store.setAudioFilters(filters) }
    }

    private func label(_ filter: AudioFilter) -> String {
        switch filter {
        case .custom(let reference): "\(reference.id.name) v\(reference.id.version)"
        case .lowPass(let frequency): "Low pass \(Int(frequency)) Hz"
        case .highPass(let frequency): "High pass \(Int(frequency)) Hz"
        case .parametricEQ(let frequency, let gain, _): "EQ \(Int(frequency)) Hz, \(String(format: "%.1f", gain)) dB"
        }
    }
}
