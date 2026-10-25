// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import AVFoundation
import CoreGraphics
import ImageIO
import Foundation

/// Encode actual exported video frames or numbered UI capture PNGs as a looping GIF.
@main struct CreateGIF {
    static func main() async throws {
        guard CommandLine.arguments.count == 5, let width = Int(CommandLine.arguments[4]), width > 0 else {
            print("Usage: CreateGIF video|frames input output.gif width")
            exit(2)
        }
        let mode = CommandLine.arguments[1]
        let input = URL(fileURLWithPath: CommandLine.arguments[2])
        let output = URL(fileURLWithPath: CommandLine.arguments[3])
        let images: [(CGImage, Double)]
        if mode == "video" {
            let asset = AVURLAsset(url: input)
            let duration = try await asset.load(.duration).seconds
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: width, height: width)
            generator.requestedTimeToleranceBefore = .zero
            generator.requestedTimeToleranceAfter = .zero
            var frames: [(CGImage, Double)] = []
            for index in 0..<Int(ceil(min(duration, 15) * 10)) {
                let image = try await generator.image(at: CMTime(seconds: Double(index) / 10, preferredTimescale: 600)).image
                frames.append((image, 0.1))
            }
            images = frames
        } else if mode == "frames" {
            let files = try FileManager.default.contentsOfDirectory(at: input, includingPropertiesForKeys: nil)
                .filter { $0.pathExtension == "png" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            images = try files.map { file in
                guard let source = CGImageSourceCreateWithURL(file as CFURL, nil),
                      let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                        kCGImageSourceCreateThumbnailFromImageAlways: true,
                        kCGImageSourceThumbnailMaxPixelSize: width
                      ] as CFDictionary) else { throw Failure.decode }
                return (image, 0.4)
            }
        } else { throw Failure.mode }
        guard !images.isEmpty, let destination = CGImageDestinationCreateWithURL(output as CFURL, "com.compuserve.gif" as CFString, images.count, nil) else {
            throw Failure.output
        }
        CGImageDestinationSetProperties(destination, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
        for (image, delay) in images {
            CGImageDestinationAddImage(destination, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: delay]] as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw Failure.output }
        print("Created \(output.path) with \(images.count) frames.")
    }
    enum Failure: Error { case decode, mode, output }
}
