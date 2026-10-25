// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import CoreImage
import Foundation

/// Generate portable H.264 footage and an original ambient soundtrack from the bundled artwork.
@main struct GenerateDemoMedia {
    static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count == 3 else { fatalError("Usage: GenerateDemoMedia <coast.png> <output-directory>") }
        let sourceURL = URL(fileURLWithPath: arguments[1])
        let folder = URL(fileURLWithPath: arguments[2])
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        guard let image = CIImage(contentsOf: sourceURL) else { throw CocoaError(.fileReadCorruptFile) }
        for shot in 0..<2 {
            let output = folder.appendingPathComponent(shot == 0 ? "coast-wide.mp4" : "coast-close.mp4")
            if FileManager.default.fileExists(atPath: output.path) { try FileManager.default.removeItem(at: output) }
            try await video(image, shot: shot, output: output)
        }
        try music(folder.appendingPathComponent("ambient.wav"))
        print("Generated two 4-second videos and an 8-second original soundtrack in \(folder.path)")
    }

    static func video(_ image: CIImage, shot: Int, output: URL) async throws {
        let width = 1280, height = 720, fps = 30, frameCount = 120
        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 2_500_000,
                                             AVVideoProfileLevelKey: AVVideoProfileLevelH264MainAutoLevel]
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height
        ])
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        writer.startSession(atSourceTime: .zero)
        let context = CIContext(options: [.cacheIntermediates: false])
        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { try await Task.sleep(for: .milliseconds(2)) }
            guard let pool = adaptor.pixelBufferPool else { throw CocoaError(.fileWriteUnknown) }
            var pixels: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixels) == kCVReturnSuccess, let pixels else { throw CocoaError(.fileWriteUnknown) }
            let t = Double(frame) / Double(frameCount - 1)
            let scale = Double(width) / image.extent.width * (shot == 0 ? 1.04 + t * 0.08 : 1.5 - t * 0.1)
            let x = shot == 0 ? -t * 40 : -Double(width) * (0.3 - t * 0.08)
            let y = shot == 0 ? -12.0 : -100.0
            let rendered = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                .transformed(by: CGAffineTransform(translationX: x, y: y)).cropped(to: canvas)
            context.render(rendered, to: pixels, bounds: canvas, colorSpace: CGColorSpaceCreateDeviceRGB())
            guard adaptor.append(pixels, withPresentationTime: CMTime(value: Int64(frame), timescale: Int32(fps))) else {
                throw writer.error ?? CocoaError(.fileWriteUnknown)
            }
        }
        input.markAsFinished()
        writer.endSession(atSourceTime: CMTime(value: 4, timescale: 1))
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }

    static func music(_ output: URL) throws {
        let rate = 48_000, count = 48_000 * 8
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) {
            var little = value.littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: "RIFF".utf8); append(UInt32(36 + count * 4)); data.append(contentsOf: "WAVEfmt ".utf8)
        append(UInt32(16)); append(UInt16(1)); append(UInt16(2)); append(UInt32(rate)); append(UInt32(rate * 4))
        append(UInt16(4)); append(UInt16(16)); data.append(contentsOf: "data".utf8); append(UInt32(count * 4))
        for index in 0..<count {
            let t = Double(index) / Double(rate)
            let swell = 0.72 + 0.28 * sin(t * .pi / 4)
            let tone = (sin(t * 2 * .pi * 130.8128) + 0.6 * sin(t * 2 * .pi * 164.8138)
                        + 0.4 * sin(t * 2 * .pi * 195.9977)) * 4500 * swell
            append(Int16(tone)); append(Int16(tone * (0.97 + 0.03 * sin(t))))
        }
        try data.write(to: output)
    }
}
