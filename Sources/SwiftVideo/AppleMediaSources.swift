// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import AVFoundation
import CoreImage

extension VideoTime {
    var cmTime: CMTime { CMTime(value: value, timescale: timescale) }
}

/// These decoder objects are owned exclusively by one AppleVideoRenderer operation.
/// Only the current decoded sample and one look-ahead sample are retained.
final class AppleVideoSource {
    let reader: AVAssetReader
    private let output: AVAssetReaderVideoCompositionOutput
    private var current: CMSampleBuffer?
    private var next: CMSampleBuffer?

    init(asset: AVAsset, track: AVAssetTrack, clip: MediaClip, rate: FrameRate,
         isolation: isolated (any Actor)? = #isolation) async throws {
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderVideoCompositionOutput(videoTracks: [track], videoSettings: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        if #available(iOS 26, macOS 26, *) {
            var configuration = try await AVVideoComposition.Configuration(for: asset)
            configuration.frameDuration = try VideoTime(frames: 1, rate: rate).cmTime
            output.videoComposition = AVVideoComposition(configuration: configuration)
        } else {
            output.videoComposition = try await AVVideoComposition.videoComposition(withPropertiesOf: asset)
        }
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoError.invalidMedia("Cannot decode video track.") }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: clip.sourceStart.cmTime, duration: clip.duration.cmTime)
        guard reader.startReading() else { throw VideoError.invalidMedia(reader.error?.localizedDescription ?? "Cannot start video reader.") }
        next = output.copyNextSampleBuffer()
    }

    func image(at time: VideoTime) throws -> CIImage {
        while let candidate = next, current == nil || CMSampleBufferGetPresentationTimeStamp(candidate) <= time.cmTime {
            current = candidate
            next = output.copyNextSampleBuffer()
        }
        if reader.status == .failed { throw VideoError.invalidMedia(reader.error?.localizedDescription ?? "Video decoding failed.") }
        guard let current, let buffer = CMSampleBufferGetImageBuffer(current) else {
            throw VideoError.invalidMedia("The requested video range contains no decoded frames.")
        }
        return CIImage(cvPixelBuffer: buffer)
    }

    deinit { reader.cancelReading() }
}

final class AppleAudioSource {
    static let sampleRate: Int32 = 48_000
    let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var samples: [Float] = []
    private var startFrame: Int64 = 0
    private var finished = false

    init(asset: AVAsset, track: AVAssetTrack, clip: MediaClip) throws {
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: Self.sampleRate,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false,
            AVLinearPCMIsBigEndianKey: false
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw VideoError.invalidMedia("Cannot decode audio track.") }
        reader.add(output)
        reader.timeRange = CMTimeRange(start: clip.sourceStart.cmTime, duration: clip.duration.cmTime)
        guard reader.startReading() else { throw VideoError.invalidMedia(reader.error?.localizedDescription ?? "Cannot start audio reader.") }
    }

    func sample(at frame: Int64) throws -> (Float, Float) {
        while !finished && (samples.isEmpty || frame >= startFrame + Int64(samples.count / 2)) {
            guard let buffer = output.copyNextSampleBuffer() else {
                finished = true
                if reader.status == .failed { throw VideoError.invalidMedia(reader.error?.localizedDescription ?? "Audio decoding failed.") }
                break
            }
            guard let data = CMSampleBufferGetDataBuffer(buffer) else { throw VideoError.invalidMedia("Audio decoder returned no PCM data.") }
            startFrame = CMTimeConvertScale(CMSampleBufferGetPresentationTimeStamp(buffer), timescale: Self.sampleRate, method: .roundHalfAwayFromZero).value
            let byteCount = CMBlockBufferGetDataLength(data)
            guard byteCount.isMultiple(of: 8) else { throw VideoError.invalidMedia("Unexpected stereo PCM layout.") }
            guard byteCount > 0 else { samples = []; continue }
            samples = [Float](repeating: 0, count: byteCount / MemoryLayout<Float>.size)
            let status = samples.withUnsafeMutableBytes {
                // A nonempty Float buffer always has a base address.
                CMBlockBufferCopyDataBytes(data, atOffset: 0, dataLength: byteCount, destination: $0.baseAddress!)
            }
            guard status == noErr else { throw VideoError.invalidMedia("Cannot read decoded PCM data (\(status)).") }
        }
        let index = frame - startFrame
        guard index >= 0, index < Int64(samples.count / 2) else { return (0, 0) }
        return (samples[Int(index) * 2], samples[Int(index) * 2 + 1])
    }

    deinit { reader.cancelReading() }
}
#endif
