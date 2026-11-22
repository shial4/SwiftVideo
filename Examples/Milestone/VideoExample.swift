// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation
import SwiftVideo

@main
struct VideoExample {
    static func main() async throws {
        let arguments = Array(CommandLine.arguments.dropFirst())
        let titles = arguments.count == 2 && arguments[0] == "motion-titles"
        guard titles || (arguments.count == 3 && (arguments[0] == "milestone" || arguments[0] == "export")) else {
            print("Usage: SwiftVideoExample milestone <asset-directory> <output.mp4>")
            print("       SwiftVideoExample export <project.json> <output.mp4>")
            print("       SwiftVideoExample motion-titles <output.mp4>")
            print("Milestone assets: red.mp4 and blue.mp4 (1 second each), green.png, music.wav (2 seconds).")
            return
        }
        let project: VideoProject
        if titles {
            project = try motionTitles()
        } else if arguments[0] == "milestone" {
            project = try milestone(in: URL(fileURLWithPath: arguments[1]))
        } else {
            project = try JSONDecoder().decode(VideoProject.self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
        }
        let output = URL(fileURLWithPath: arguments[titles ? 1 : 2])
        let exporter = VideoExporter()
        try await exporter.export(project, to: output,
            settings: ExportSettings(resolution: titles ? project.canvas : .hd1080, videoBitRate: 4_000_000)) {
            if $0.phase != .rendering { print("\($0.phase.rawValue): \(Int($0.fraction * 100))%") }
        }
        print("Exported \(output.path)")
    }

    private static func motionTitles() throws -> VideoProject {
        let two = try VideoTime(value: 2, timescale: 1)
        let half = try VideoTime(value: 1, timescale: 2)
        let tenth = try VideoTime(value: 1, timescale: 10)
        let motions: [TextMotion] = [.typewriter(stagger: tenth), .fadeUp(duration: half, stagger: tenth),
                                    try .pop(duration: half, stagger: tenth)]
        let labels = ["WRITE YOUR STORY", "MAKE WORDS MOVE", "BUILD WITH SWIFT"]
        return try VideoProject(canvas: VideoSize(width: 640, height: 360),
            background: VideoColor(red: 0.04, green: 0.08, blue: 0.18)) {
            try MediaTrack("Motion titles") {
                for index in motions.indices {
                    MediaClip.text(labels[index], duration: two,
                        style: TextStyle(fontSize: 44, shadow: TextShadow(radius: 3)))
                        .starting(at: try VideoTime(value: Int64(index * 2), timescale: 1))
                        .textMotion(motions[index])
                        .transform(VisualTransform(y: 0.5, width: 0.9, height: 0.25))
                }
            }
        }
    }

    private static func milestone(in folder: URL) throws -> VideoProject {
        let one = try VideoTime(value: 1, timescale: 1)
        let two = try VideoTime(value: 2, timescale: 1)
        let quarter = try VideoTime(value: 1, timescale: 4)
        let half = try VideoTime(value: 1, timescale: 2)
        return VideoProject(tracks: [
            MediaTrack(name: "Footage", clips: [
                MediaClip(source: .video(folder.appendingPathComponent("red.mp4")), duration: one),
                MediaClip(source: .video(folder.appendingPathComponent("blue.mp4")), start: one, duration: one)
            ]),
            MediaTrack(name: "Overlays", clips: [
                MediaClip(source: .text("SWIFT VIDEO", TextStyle(fontSize: 120, shadow: TextShadow())), duration: two, zIndex: 2,
                    transform: VisualTransform(y: 0.4, width: 0.6, height: 0.3), animations: [
                        KeyframeAnimation(property: .x, keyframes: [Keyframe(time: .zero, value: 0.3), Keyframe(time: two, value: 0.7)]),
                        KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: half, value: 1)])
                    ]),
                MediaClip(source: .image(folder.appendingPathComponent("green.png")), duration: two, zIndex: 1,
                    transform: VisualTransform(x: 0.85, y: 0.8, width: 0.2, height: 0.2, contentMode: .stretch))
            ]),
            MediaTrack(name: "Music", clips: [
                MediaClip(source: .audio(folder.appendingPathComponent("music.wav")), duration: two,
                          audio: AudioSettings(volume: 0.5, fadeIn: quarter, fadeOut: quarter))
            ])
        ])
    }
}
