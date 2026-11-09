// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import AVFoundation

/// Confined to one export operation. Decoding and offline rendering advance monotonically.
final class AppleClipAudioSource {
    private let source: AppleAudioSource
    private let processor: AppleAudioProcessor?
    private let origin: Int64

    init(asset: AVAsset, track: AVAssetTrack, clip: MediaClip, effects: EffectRegistry = .empty) throws {
        source = try AppleAudioSource(asset: asset, track: track, clip: clip)
        origin = CMTimeConvertScale(clip.sourceStart.cmTime, timescale: AppleAudioSource.sampleRate, method: .roundHalfAwayFromZero).value
        processor = clip.playbackRate == .normal && clip.audio.filters.isEmpty ? nil : try AppleAudioProcessor(source: source, clip: clip, effects: effects)
    }

    func sample(at frame: Int64) throws -> (Float, Float) {
        if let processor { return try processor.sample(at: frame) }
        return try source.sample(at: frame + origin)
    }
}

/// Bounded offline PCM pipeline: decoder -> time stretch -> ordered EQ -> mixer.
/// Player buffers are supplied only a fixed look-ahead beyond the requested output time.
/// No audio-device session, realtime callback, or whole-file PCM allocation is needed.
private final class AppleAudioProcessor {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let source: AppleAudioSource
    private let format: AVAudioFormat
    private let output: AVAudioPCMBuffer
    private let rate: Double
    private let origin: Int64
    private let sourceFrames: Int64
    private var supplied: Int64 = 0
    private var rendered: Int64 = 0
    private var latencyFrames: Int64 = 0
    private var blockStart: Int64 = 0
    private var samples: [Float] = []
    private var custom: AudioEffectChain?
    private let outputFrames: Int64

    init(source: AppleAudioSource, clip: MediaClip, effects: EffectRegistry) throws {
        self.source = source
        rate = clip.playbackRate.multiplier
        origin = CMTimeConvertScale(clip.sourceStart.cmTime, timescale: AppleAudioSource.sampleRate, method: .roundHalfAwayFromZero).value
        sourceFrames = CMTimeConvertScale(try clip.sourceDuration.cmTime, timescale: AppleAudioSource.sampleRate, method: .roundAwayFromZero).value
        outputFrames = CMTimeConvertScale(clip.duration.cmTime, timescale: AppleAudioSource.sampleRate, method: .roundAwayFromZero).value
        guard let format = AVAudioFormat(standardFormatWithSampleRate: Double(AppleAudioSource.sampleRate), channels: 2),
              let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024) else {
            throw VideoError.renderingFailed("Cannot allocate audio processing buffers.")
        }
        self.format = format; self.output = output
        // Enter offline mode before touching the graph. Accessing the main mixer
        // first initializes device I/O, which can block or abort in headless exports.
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: output.frameCapacity)
        engine.attach(player)
        var last: AVAudioNode = player
        if clip.playbackRate != .normal {
            let stretch = AVAudioUnitTimePitch()
            stretch.rate = Float(rate); stretch.pitch = 0
            engine.attach(stretch); engine.connect(last, to: stretch, format: format)
            last = stretch
        }
        // Separate units preserve authored order even when filters have different kinds.
        let usesCustom = clip.audio.filters.contains(where: \.isCustom)
        for filter in usesCustom ? [] : clip.audio.filters {
            let equalizer = AVAudioUnitEQ(numberOfBands: 1)
            let band = equalizer.bands[0]
            band.bypass = false
            switch filter {
            case .custom: continue
            case .lowPass(let frequency): band.filterType = .lowPass; band.frequency = Float(frequency)
            case .highPass(let frequency): band.filterType = .highPass; band.frequency = Float(frequency)
            case .parametricEQ(let frequency, let gain, let bandwidth):
                band.filterType = .parametric; band.frequency = Float(frequency)
                band.gain = Float(gain); band.bandwidth = Float(bandwidth)
            }
            engine.attach(equalizer); engine.connect(last, to: equalizer, format: format)
            last = equalizer
        }
        engine.connect(last, to: engine.mainMixerNode, format: format)
        engine.prepare()
        try engine.start()
        latencyFrames = Int64((engine.attachedNodes.reduce(0) { $0 + $1.latency } * format.sampleRate).rounded(.up))
        player.play()
        if usesCustom {
            custom = try AudioEffectChain(clip: clip, registry: effects, platform: .apple,
                format: AudioEffectFormat(sampleRate: Int(AppleAudioSource.sampleRate), channels: 2))
        }
    }

    func sample(at frame: Int64) throws -> (Float, Float) {
        guard frame >= 0 else { return (0, 0) }
        let target = frame + latencyFrames
        while samples.isEmpty || target >= blockStart + Int64(samples.count / 2) {
            try Task.checkCancellation()
            // At most about 0.8 seconds of stereo PCM is scheduled ahead, independent of file length.
            let required = Int64((Double(rendered + 1024) * rate).rounded(.up)) + 32_768
            while supplied < required { try supplyBuffer() }
            blockStart = rendered
            var attempts = 0
            while true {
                let status = try engine.renderOffline(1024, to: output)
                if status == .success || status == .insufficientDataFromInputNode {
                    guard output.frameLength > 0 else { throw VideoError.renderingFailed("Audio processor made no progress.") }
                    break
                }
                attempts += 1
                guard status == .cannotDoInCurrentContext, attempts < 10 else {
                    throw VideoError.renderingFailed("Offline audio processing failed.")
                }
                try Task.checkCancellation()
            }
            guard let channels = output.floatChannelData else { throw VideoError.renderingFailed("Audio processor returned no PCM.") }
            let count = Int(output.frameLength)
            // Priming samples are discarded before custom DSP. Its first buffer starts
            // at the selected clip's time, without feeding time-stretch latency into delay lines.
            let skip = custom == nil ? 0 : Int(min(Int64(count), max(0, latencyFrames - rendered)))
            let end = custom == nil ? count : Int(min(Int64(count), max(Int64(skip), outputFrames + latencyFrames - rendered)))
            blockStart += Int64(skip)
            samples = [Float](repeating: 0, count: (end - skip) * 2)
            for index in skip..<end {
                samples[(index - skip) * 2] = channels[0][index]; samples[(index - skip) * 2 + 1] = channels[1][index]
            }
            if !samples.isEmpty { try custom?.process(&samples) }
            rendered += Int64(count)
            if samples.isEmpty && rendered >= outputFrames + latencyFrames { return (0, 0) }
        }
        let index = Int(target - blockStart) * 2
        guard index >= 0 else { throw VideoError.renderingFailed("Audio processing requires increasing sample positions.") }
        return (samples[index], samples[index + 1])
    }

    private func supplyBuffer() throws {
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096), let channels = buffer.floatChannelData else {
            throw VideoError.renderingFailed("Cannot allocate audio input buffer.")
        }
        buffer.frameLength = buffer.frameCapacity
        for index in 0..<Int(buffer.frameLength) {
            let position = supplied + Int64(index)
            let pair = position < sourceFrames ? try source.sample(at: origin + position) : (Float(0), Float(0))
            channels[0][index] = pair.0; channels[1][index] = pair.1
        }
        // Zero input beyond the selected source range drains latency without extending the timeline.
        player.scheduleBuffer(buffer)
        supplied += Int64(buffer.frameLength)
    }

    deinit { custom?.finish(); player.stop(); engine.stop() }
}
#endif
