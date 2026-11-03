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
        let onset = Double(reference.offsetFrames) / 48000
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
                let t = time + Double(frame) / 48000
                let value = Double(values[frame * 2]) / 32768
                if t < onset { leadingPeak = max(leadingPeak, abs(value)) }
                if t >= onset && t < onset + 0.05 { squares[0] += value * value; counts[0] += 1 }
                if t >= 0.5 && t < 0.55 { squares[1] += value * value; counts[1] += 1 }
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
}
#endif
