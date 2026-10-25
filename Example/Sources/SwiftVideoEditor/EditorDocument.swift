// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftVideo

enum EditorTool: String, CaseIterable, Identifiable {
    case edit = "Edit", text = "Text", filters = "Filters", audio = "Audio", overlay = "Overlay"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .edit: "scissors"; case .text: "textformat"; case .filters: "slider.horizontal.3"
        case .audio: "music.note"; case .overlay: "square.on.square" }
    }
}

enum EditorFilter: String, CaseIterable, Identifiable {
    case original = "Original", warm = "Golden", vivid = "Vivid", mono = "Mono", dream = "Dream"
    var id: String { rawValue }
    var effects: [MediaFilter] {
        switch self {
        case .original: []
        case .warm: [.sepia(0.35), .saturation(1.2)]
        case .vivid: [.contrast(1.12), .saturation(1.55)]
        case .mono: [.saturation(0), .contrast(1.1)]
        case .dream: [.gaussianBlur(3), .brightness(0.08)]
        }
    }
}

struct DemoAssets: Sendable {
    let wide: URL
    let close: URL
    let coast: URL
    let music: URL

    static func load() throws -> DemoAssets {
        func asset(_ name: String, _ ext: String) throws -> URL {
            guard let source = Bundle.module.url(forResource: name, withExtension: ext)
                    ?? Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Demo") else {
                throw VideoError.invalidMedia("Missing bundled demo asset: \(name).\(ext)")
            }
            // APK resources may not be ordinary files. Materialize once in the app cache.
            let folder = FileManager.default.temporaryDirectory.appendingPathComponent("SwiftVideoDemoAssets")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let output = folder.appendingPathComponent("\(name).\(ext)")
            if !FileManager.default.fileExists(atPath: output.path) { try Data(contentsOf: source).write(to: output, options: .atomic) }
            return output
        }
        return try DemoAssets(wide: asset("coast-wide", "mp4"), close: asset("coast-close", "mp4"),
                              coast: asset("coast", "png"), music: asset("ambient", "wav"))
    }

    func project() throws -> VideoProject {
        let four = try seconds(4), eight = try seconds(8), fade = try seconds(0.5)
        let captionStyle = TextStyle(fontSize: 64, shadow: TextShadow(radius: 6, x: 2, y: 2))
        let captions: [(String, Double, Double)] = [
            ("Golden light. Open water.", 2.5, 1.5),
            ("A second angle brings the coast closer.", 4, 2),
            ("Two perspectives. One story.", 6, 2)
        ]
        return try VideoProject {
            MediaTrack("Footage") {
                MediaClip.video(wide, duration: four).audio(AudioSettings(isMuted: true))
                MediaClip.video(close, duration: four).starting(at: four).audio(AudioSettings(isMuted: true))
            }
            try MediaTrack("Titles") {
                try MediaClip.text("COASTAL\nESCAPE", duration: seconds(2.2),
                               style: TextStyle(fontSize: 150, shadow: TextShadow(radius: 8)))
                    .starting(at: seconds(0.2)).zIndex(10)
                    .transform(VisualTransform(x: 0.64, y: 0.48, width: 0.62, height: 0.4))
                    .animate(.opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: fade, value: 1)])
                    .animate(.y, keyframes: [Keyframe(time: .zero, value: 0.55, easing: .easeOut), Keyframe(time: fade, value: 0.48)])
                for (text, start, length) in captions {
                    try MediaClip.text(text, duration: seconds(length), style: captionStyle)
                        .starting(at: seconds(start)).zIndex(20)
                        .transform(VisualTransform(y: 0.89, width: 0.92, height: 0.13))
                }
            }
            try MediaTrack("Overlays") {
                try MediaClip.image(coast, duration: seconds(2.5)).zIndex(5)
                    .transform(VisualTransform(x: 0.18, y: 0.48, width: 0.25, height: 0.62, rotation: -4, contentMode: .fill))
                    .animate(.opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: fade, value: 1)])
                MediaClip.video(wide, duration: four).starting(at: four).zIndex(5)
                    .transform(VisualTransform(x: 0.78, y: 0.29, width: 0.35, height: 0.35, contentMode: .fill))
                    .audio(AudioSettings(isMuted: true))
            }
            try MediaTrack("Soundtrack") {
                try MediaClip.audio(music, duration: eight)
                    .audio(AudioSettings(volume: 0.6, fadeIn: fade, fadeOut: seconds(1)))
            }
        }
    }
}

func seconds(_ value: Double) throws -> VideoTime {
    guard value.isFinite, abs(value) < Double(Int64.max / 600) else { throw VideoError.timeOverflow }
    return try VideoTime(value: Int64((value * 600).rounded()), timescale: 600)
}

extension MediaClip {
    var displayName: String {
        switch source {
        case .video(let url): url.lastPathComponent == "coast-wide.mp4" ? "Coast / wide" : "Coast / detail"
        case .image: "Image overlay"
        case .text(let text, _): text
        case .audio: "Golden hour / ambient"
        }
    }

}
