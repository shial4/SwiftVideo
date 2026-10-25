// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import ImageIO
import Testing
@testable import SwiftVideo

@Suite struct AppleExportTests {
    @Test @MainActor func milestoneExportsMergedVideoAnimatedTextImageAndFadingMusic() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftvideo-integration-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let red = folder.appendingPathComponent("red.mp4")
        let blue = folder.appendingPathComponent("blue.mp4")
        let image = folder.appendingPathComponent("green.png")
        let music = folder.appendingPathComponent("music.wav")
        try await makeVideo(red, color: CIColor(red: 1, green: 0, blue: 0))
        try await makeVideo(blue, color: CIColor(red: 0, green: 0, blue: 1))
        try makeImage(image)
        try makeMusic(music)
        if let path = ProcessInfo.processInfo.environment["SWIFTVIDEO_FIXTURE_OUTPUT"] {
            let output = URL(fileURLWithPath: path)
            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
            for fixture in [red, blue, image, music] {
                let destination = output.appendingPathComponent(fixture.lastPathComponent)
                if FileManager.default.fileExists(atPath: destination.path) { try FileManager.default.removeItem(at: destination) }
                try FileManager.default.copyItem(at: fixture, to: destination)
            }
        }

        let one = try VideoTime(value: 1, timescale: 1)
        let two = try VideoTime(value: 2, timescale: 1)
        let half = try VideoTime(value: 1, timescale: 2)
        let quarter = try VideoTime(value: 1, timescale: 4)
        let project = VideoProject(tracks: [
            MediaTrack(name: "Footage", clips: [MediaClip(source: .video(red), duration: one),
                                                MediaClip(source: .video(blue), start: one, duration: one)]),
            MediaTrack(name: "Overlays", clips: [
                MediaClip(source: .text("SWIFT VIDEO", TextStyle(fontSize: 120)), duration: two, zIndex: 2,
                    transform: VisualTransform(y: 0.4, width: 0.6, height: 0.3), animations: [
                        KeyframeAnimation(property: .x, keyframes: [Keyframe(time: .zero, value: 0.3), Keyframe(time: two, value: 0.7)]),
                        KeyframeAnimation(property: .opacity, keyframes: [Keyframe(time: .zero, value: 0), Keyframe(time: half, value: 1)])
                    ]),
                MediaClip(source: .image(image), duration: two, zIndex: 1,
                    transform: VisualTransform(x: 0.85, y: 0.8, width: 0.2, height: 0.2, contentMode: .stretch))
            ]),
            MediaTrack(name: "Music", clips: [MediaClip(source: .audio(music), duration: two,
                                                       audio: AudioSettings(volume: 0.5, fadeIn: quarter, fadeOut: quarter))])
        ])
        let destination = folder.appendingPathComponent("milestone.mp4")
        let (events, continuation) = AsyncStream<ExportProgress>.makeStream()
        let collecting = Task { var result: [ExportProgress] = []; for await event in events { result.append(event) }; return result }
        let exporter = VideoExporter()
        try await exporter.export(project, to: destination,
            settings: ExportSettings(resolution: VideoSize(width: 320, height: 180), videoBitRate: 500_000)) {
            continuation.yield($0)
        }
        continuation.finish()
        let progress = await collecting.value
        #expect(progress.last == ExportProgress(phase: .completed, fraction: 1))
        #expect(zip(progress, progress.dropFirst()).allSatisfy { $0.fraction <= $1.fraction })

        let asset = AVURLAsset(url: destination)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        #expect(try await track.load(.naturalSize) == CGSize(width: 320, height: 180))
        #expect(abs(try await asset.load(.duration).seconds - 2) < 0.04)
        #expect(abs(try await track.load(.nominalFrameRate) - 30) < 0.1)
        let first = try await frame(asset, at: 0.5)
        let second = try await frame(asset, at: 1.5)
        let redPixel = pixel(first, x: first.width / 2, y: first.height * 5 / 9)
        let bluePixel = pixel(second, x: second.width / 2, y: second.height * 5 / 9)
        #expect(redPixel.0 > 180 && redPixel.2 < 80)
        #expect(bluePixel.2 > 180 && bluePixel.0 < 80)
        let overlay = pixel(second, x: second.width * 85 / 100, y: second.height * 4 / 5)
        #expect(overlay.1 > 180 && overlay.0 < 80 && overlay.2 < 80)
        let leftTitle = try #require(whiteCentroid(first))
        let rightTitle = try #require(whiteCentroid(second))
        #expect(rightTitle > leftTitle + Double(first.width) * 0.08)

        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let outputClip = MediaClip(source: .audio(destination), duration: two)
        let audio = try AppleAudioSource(asset: asset, track: audioTrack, clip: outputClip)
        let beginning = try rms(audio, start: 0, count: 2400)
        let middle = try rms(audio, start: 24_000, count: 2400)
        let ending = try rms(audio, start: 93_000, count: 2400)
        #expect(middle > 0.05)
        #expect(beginning < middle * 0.4)
        #expect(ending < middle * 0.4)
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).allSatisfy { !$0.hasPrefix(".swiftvideo-") })
    }

    @Test func textRendersUprightWithinItsLayerBounds() async throws {
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("text-orientation-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: output) }
        let clip = MediaClip.text("L", duration: try VideoTime(value: 1, timescale: 1),
                                  style: TextStyle(fontSize: 100, alignment: .leading))
            .transform(VisualTransform(width: 0.8, height: 0.8))
        try await VideoExporter().export(VideoProject(canvas: VideoSize(width: 320, height: 180)) {
            MediaTrack { clip }
        }, to: output)
        let image = try await frame(AVURLAsset(url: output), at: 0.5)
        let bytes = rgba(image)
        var rows = [Int](repeating: 0, count: image.height)
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                if bytes[offset] > 200 && bytes[offset + 1] > 200 && bytes[offset + 2] > 200 { rows[y] += 1 }
            }
        }
        let top = try #require(rows.firstIndex(where: { $0 > 0 }))
        let bottom = try #require(rows.lastIndex(where: { $0 > 0 }))
        #expect(bottom - top > 50)
        let quarter = max(1, (bottom - top) / 4)
        let upper = rows[top..<(top + quarter)].reduce(0, +)
        let lower = rows[(bottom - quarter + 1)...bottom].reduce(0, +)
        // The horizontal foot of an upright L contains more white pixels at the bottom.
        #expect(lower > upper * 2, "Text pixel counts: upper=\(upper), lower=\(lower)")
    }

    @Test func missingMediaLeavesNoPartialOutput() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("swiftvideo-failure-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clip = MediaClip(source: .video(folder.appendingPathComponent("missing.mp4")), duration: try VideoTime(value: 1, timescale: 1))
        await #expect(throws: VideoError.self) {
            try await VideoExporter().export(VideoProject(tracks: [MediaTrack(clips: [clip])]), to: folder.appendingPathComponent("output.mp4"))
        }
        #expect(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }

    @MainActor private func makeVideo(_ url: URL, color: CIColor) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [AVVideoCodecKey: AVVideoCodecType.h264,
                                                                        AVVideoWidthKey: 320, AVVideoHeightKey: 180])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: 320, kCVPixelBufferHeightKey as String: 180
        ])
        writer.add(input)
        #expect(writer.startWriting())
        writer.startSession(atSourceTime: .zero)
        let pool = try #require(adaptor.pixelBufferPool)
        let context = CIContext()
        for index in 0..<30 {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            var buffer: CVPixelBuffer?
            #expect(CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess)
            let pixels = try #require(buffer)
            context.render(CIImage(color: color).cropped(to: CGRect(x: 0, y: 0, width: 320, height: 180)), to: pixels)
            #expect(adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(index), timescale: 30)))
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 1, timescale: 1))
        await writer.finishWriting()
        #expect(writer.status == .completed)
    }

    private func makeImage(_ url: URL) throws {
        let context = CIContext()
        let source = CIImage(color: CIColor(red: 0, green: 1, blue: 0)).cropped(to: CGRect(x: 0, y: 0, width: 64, height: 64))
        let image = try #require(context.createCGImage(source, from: source.extent))
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
    }

    private func makeMusic(_ url: URL) throws {
        let rate = 48_000
        let count = rate * 2
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + count * 4)); data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2)); append(UInt32(rate)); append(UInt32(rate * 4))
        append(UInt16(4)); append(UInt16(16)); data.append(contentsOf: "data".utf8); append(UInt32(count * 4))
        for index in 0..<count {
            let value = Int16(sin(Double(index) / Double(rate) * 440 * 2 * .pi) * 20_000)
            append(value); append(value)
        }
        try data.write(to: url)
    }

    private func frame(_ asset: AVAsset, at seconds: Double) async throws -> CGImage {
        let generator = AVAssetImageGenerator(asset: asset)
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        bytes.withUnsafeMutableBytes { buffer in
            // The positive image dimensions guarantee allocated storage and a valid bitmap context.
            let context = CGContext(data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    private func pixel(_ image: CGImage, x: Int, y: Int) -> (UInt8, UInt8, UInt8) {
        let bytes = rgba(image)
        let offset = (y * image.width + x) * 4
        return (bytes[offset], bytes[offset + 1], bytes[offset + 2])
    }

    private func whiteCentroid(_ image: CGImage) -> Double? {
        let bytes = rgba(image)
        var total = 0.0
        var count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let offset = (y * image.width + x) * 4
                if bytes[offset] > 200 && bytes[offset + 1] > 200 && bytes[offset + 2] > 200 { total += Double(x); count += 1 }
            }
        }
        return count > 0 ? total / Double(count) : nil
    }

    private func rms(_ source: AppleAudioSource, start: Int64, count: Int) throws -> Double {
        var square = 0.0
        for index in 0..<count { let sample = try source.sample(at: start + Int64(index)).0; square += Double(sample * sample) }
        return sqrt(square / Double(count))
    }
}
#endif
