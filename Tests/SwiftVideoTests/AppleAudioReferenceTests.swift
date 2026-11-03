// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !os(Android) && !SWIFTVIDEO_CORE_COVERAGE
import AVFoundation
import Foundation
import Testing

extension RenderBehaviorTests {
    @Test(arguments: AACFixtureReference.all)
    func aacReferencesMatchAppleTimeline(reference: AACFixtureReference) async throws {
        let name = (reference.name as NSString).deletingPathExtension
        let ext = (reference.name as NSString).pathExtension
        let url = try #require(Bundle.module.url(forResource: name, withExtension: ext))
        let asset = AVURLAsset(url: url)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2
        ])
        reader.add(output)
        try #require(reader.startReading())
        defer { reader.cancelReading() }
        var frames = 0
        var squares = [0.0, 0.0]
        var counts = [0, 0]
        var leadingPeak = 0.0
        while let sample = output.copyNextSampleBuffer() {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            let count = CMSampleBufferGetNumSamples(sample)
            #expect(abs(time - Double(frames) / 48000) < 0.000_001)
            let block = try #require(CMSampleBufferGetDataBuffer(sample))
            try #require(CMBlockBufferGetDataLength(block) == count * 4)
            var values = [Int16](repeating: 0, count: count * 2)
            let status = values.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: count * 4, destination: $0.baseAddress!)
            }
            try #require(status == noErr)
            for frame in 0..<count {
                let position = frames + frame
                let value = Double(values[frame * 2]) / 32768
                if position < reference.offsetFrames { leadingPeak = max(leadingPeak, abs(value)) }
                if position >= reference.offsetFrames && position < reference.offsetFrames + 2400 {
                    squares[0] += value * value; counts[0] += 1
                }
                if position >= 24_000 && position < 26_400 { squares[1] += value * value; counts[1] += 1 }
            }
            frames += count
        }
        try #require(reader.status == .completed, "Audio reference read failed: \(String(describing: reader.error))")
        #expect(frames == 96_000 + reference.offsetFrames)
        #expect(leadingPeak == 0)
        #expect(counts.allSatisfy { $0 == 2400 })
        #expect(abs(sqrt(squares[0] / Double(counts[0])) - AACFixtureReference.initialRMS) < 0.000_01)
        #expect(abs(sqrt(squares[1] / Double(counts[1])) - reference.middleRMS) < 0.000_01)
    }

    @Test func longOffsetAACMatchesOriginalPCM() async throws {
        func decode(_ name: String, start: Int64) async throws -> Data {
            let url = try #require(Bundle.module.url(forResource: name, withExtension: "mp4"))
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .audio)
            let reader = try AVAssetReader(asset: asset)
            // Inspect the authored edit range explicitly. Apple's inferred asset
            // duration can trim the last AAC packet after a long empty edit.
            reader.timeRange = CMTimeRange(start: CMTime(value: start, timescale: 1), duration: CMTime(value: 2, timescale: 1))
            let output = AVAssetReaderAudioMixOutput(audioTracks: tracks, audioSettings: [
                AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2
            ])
            reader.add(output)
            try #require(reader.startReading())
            defer { reader.cancelReading() }
            var data = Data()
            while let sample = output.copyNextSampleBuffer() {
                #expect(abs(CMSampleBufferGetPresentationTimeStamp(sample).seconds
                            - Double(start) - Double(data.count / 4) / 48000) < 0.000_001)
                let block = try #require(CMSampleBufferGetDataBuffer(sample))
                let size = CMBlockBufferGetDataLength(block)
                var bytes = Data(count: size)
                let status = bytes.withUnsafeMutableBytes {
                    CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: size, destination: $0.baseAddress!)
                }
                try #require(status == noErr)
                data.append(bytes)
            }
            try #require(reader.status == .completed)
            #expect(data.count == 96_000 * 4)
            return data
        }
        let reference = try await decode("red-with-music", start: 0)
        let delayed = try await decode("red-with-late-music", start: 360)
        #expect(delayed == reference, "The long-offset fixture must retain every original decoded sample")
    }
}
#endif
