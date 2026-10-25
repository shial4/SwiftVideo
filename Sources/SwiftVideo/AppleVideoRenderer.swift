// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import Metal

/// AVFoundation decoding/encoding, Core Image composition, and Core Animation text rendering.
public actor AppleVideoRenderer: VideoRendering {
    public nonisolated let capabilities = RendererCapabilities(
        name: "AVFoundation", features: Set(CompositionFeature.allCases),
        codecs: [.h264, .hevc], containers: [.mp4, .mov])

    public init() {}

    // CIContext is thread-safe and owns expensive Metal kernel/command-queue caches.
    // Share it across preview and export instances instead of rebuilding it per edit.
    private static let context: CIContext? = MTLCreateSystemDefaultDevice().map {
        CIContext(mtlDevice: $0, options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
    }

    public func render(_ project: VideoProject, to destination: URL, settings: ExportSettings,
                       progress: @escaping @Sendable (ExportProgress) -> Void) async throws {
        try project.validate()
        try settings.validate(for: project)
        try capabilities.validate(project, settings: settings)
        guard let context = Self.context else {
            throw VideoError.unsupportedFeature("A Metal-capable GPU is required for Apple video composition.")
        }
        let size = settings.resolution ?? project.canvas
        let rate = settings.frameRate ?? project.frameRate
        let duration = try project.duration
        guard duration > .zero else { throw VideoError.invalidProject("Cannot render an empty timeline.") }
        guard size.width <= 8192, size.height <= 8192, rate.framesPerSecond <= 240 else {
            throw VideoError.unsupportedFeature("This renderer supports output up to 8192 pixels per dimension and 240 fps.")
        }
        progress(ExportProgress(phase: .preparing, fraction: 0))
        let clips = project.tracks.flatMap(\.clips)
        let visualClips = clips.enumerated().filter { $0.element.source.isVisual }.sorted {
            $0.element.zIndex == $1.element.zIndex ? $0.offset < $1.offset : $0.element.zIndex < $1.element.zIndex
        }.map(\.element)
        var assets: [UUID: AVAsset] = [:]
        var videoTracks: [UUID: AVAssetTrack] = [:]
        var audioTracks: [UUID: AVAssetTrack] = [:]
        var images: [UUID: CIImage] = [:]
        for clip in clips {
            try Task.checkCancellation()
            switch clip.source {
            case .video(let url), .audio(let url):
                guard url.scheme != "content" else { throw VideoError.unsupportedFeature("Android content URLs cannot be read by AVFoundation.") }
                let asset = AVURLAsset(url: url)
                let assetDuration = try await asset.load(.duration)
                guard assetDuration.isNumeric, try clip.sourceStart.adding(clip.duration).cmTime <= assetDuration else {
                    throw VideoError.invalidMedia("The source range exceeds the duration of \(url.lastPathComponent).")
                }
                assets[clip.id] = asset
                if case .video = clip.source {
                    guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                        throw VideoError.invalidMedia("No video track in \(url.lastPathComponent).")
                    }
                    videoTracks[clip.id] = track
                }
                if !clip.audio.isMuted {
                    let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
                    if case .audio = clip.source, audioTrack == nil {
                        throw VideoError.invalidMedia("No audio track in \(url.lastPathComponent).")
                    }
                    audioTracks[clip.id] = audioTrack
                }
            case .image(let url):
                guard let image = CIImage(contentsOf: url, options: [.applyOrientationProperty: true]),
                      !image.extent.isEmpty, !image.extent.isInfinite else {
                    throw VideoError.invalidMedia("Cannot decode image \(url.lastPathComponent).")
                }
                images[clip.id] = image
            case .text(let text, let style):
                images[clip.id] = try await AppleFrameRenderer.textImage(text, style: style, project: project, size: size,
                                                                       rasterSize: clip.textRasterSize(for: size))
            }
        }

        let writer = try AVAssetWriter(outputURL: destination, fileType: settings.container == .mp4 ? .mp4 : .mov)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: settings.codec == .h264 ? AVVideoCodecType.h264 : AVVideoCodecType.hevc,
            AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: try settings.effectiveVideoBitRate(for: project),
                                              AVVideoExpectedSourceFrameRateKey: rate.framesPerSecond],
            AVVideoColorPropertiesKey: [AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                                       AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                                       AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2]
        ]
        guard writer.canApply(outputSettings: videoSettings, forMediaType: .video) else {
            throw VideoError.unsupportedFeature("The device encoder cannot apply the requested video settings.")
        }
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferMetalCompatibilityKey as String: true,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        guard writer.canAdd(videoInput) else { throw VideoError.unsupportedFeature("Cannot create video encoder input.") }
        writer.add(videoInput)
        var audioInput: AVAssetWriterInput?
        if !audioTracks.isEmpty {
            let audioSettings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: AppleAudioSource.sampleRate,
                                               AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: settings.audioBitRate]
            guard writer.canApply(outputSettings: audioSettings, forMediaType: .audio) else {
                throw VideoError.unsupportedFeature("The device encoder cannot apply the requested audio settings.")
            }
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            guard writer.canAdd(input) else { throw VideoError.unsupportedFeature("Cannot create audio encoder input.") }
            writer.add(input)
            audioInput = input
        }
        guard writer.startWriting() else { throw VideoError.renderingFailed(writer.error?.localizedDescription ?? "Cannot start encoder.") }
        writer.startSession(atSourceTime: .zero)
        var complete = false
        defer { if !complete { writer.cancelWriting() } }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        var videos: [UUID: AppleVideoSource] = [:]
        var audio: [UUID: AppleAudioSource] = [:]
        var frameIndex: Int64 = 0
        var audioFrame: Int64 = 0
        let audioFrames = CMTimeConvertScale(duration.cmTime, timescale: AppleAudioSource.sampleRate, method: .roundAwayFromZero).value
        var videoFinished = false
        var audioFinished = audioInput == nil
        while !videoFinished || !audioFinished {
            try Task.checkCancellation()
            let videoTime = try VideoTime(frames: frameIndex, rate: rate)
            let audioTime = try VideoTime(value: audioFrame, timescale: AppleAudioSource.sampleRate)
            if !videoFinished && videoTime >= duration {
                videoInput.markAsFinished()
                videoFinished = true
            }
            if !audioFinished && audioFrame >= audioFrames {
                audioInput?.markAsFinished()
                audioFinished = true
            }
            let videoReady = !videoFinished && videoInput.isReadyForMoreMediaData
            let audioReady = !audioFinished && (audioInput?.isReadyForMoreMediaData ?? false)
            // Feed whichever encoder can accept data. Waiting for one stream before
            // feeding the other can deadlock AVAssetWriter's interleaving queues.
            if videoReady && (!audioReady || videoTime <= audioTime) {
                for clip in clips where videoTracks[clip.id] != nil {
                    if try clip.timeRange.contains(videoTime) {
                        if videos[clip.id] == nil, let asset = assets[clip.id], let track = videoTracks[clip.id] {
                            videos[clip.id] = try await AppleVideoSource(asset: asset, track: track, clip: clip, rate: rate)
                        }
                    } else { videos[clip.id] = nil }
                }
                guard let pool = adaptor.pixelBufferPool else { throw VideoError.renderingFailed("Video encoder has no pixel buffer pool.") }
                var buffer: CVPixelBuffer?
                guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer) == kCVReturnSuccess, let buffer else {
                    throw VideoError.renderingFailed("Cannot allocate output video frame.")
                }
                try autoreleasepool {
                    let image = try AppleFrameRenderer.compose(project, visualClips: visualClips, at: videoTime, size: size, videos: videos, images: images)
                    context.render(image, to: buffer, bounds: CGRect(x: 0, y: 0, width: size.width, height: size.height), colorSpace: colorSpace)
                }
                guard adaptor.append(buffer, withPresentationTime: videoTime.cmTime) else {
                    throw VideoError.renderingFailed(writer.error?.localizedDescription ?? "Cannot encode video frame.")
                }
                frameIndex += 1
                progress(ExportProgress(phase: .rendering, fraction: 0.95 * min(1, videoTime.seconds / duration.seconds)))
            } else if let audioInput, audioReady {
                let count = Int(min(1024, audioFrames - audioFrame))
                let endTime = try VideoTime(value: audioFrame + Int64(count), timescale: AppleAudioSource.sampleRate)
                for clip in clips where audioTracks[clip.id] != nil {
                    if try clip.start < endTime && clip.timeRange.end > audioTime {
                        if audio[clip.id] == nil, let asset = assets[clip.id], let track = audioTracks[clip.id] {
                            audio[clip.id] = try AppleAudioSource(asset: asset, track: track, clip: clip)
                        }
                    } else { audio[clip.id] = nil }
                }
                let samples = try mixAudio(clips: clips, sources: audio, startFrame: audioFrame, count: count)
                let buffer = try makeAudioBuffer(samples, startFrame: audioFrame)
                guard audioInput.append(buffer) else { throw VideoError.renderingFailed(writer.error?.localizedDescription ?? "Cannot encode audio samples.") }
                audioFrame += Int64(count)
            } else if !videoFinished || !audioFinished {
                guard writer.status == .writing else {
                    throw VideoError.renderingFailed(writer.error?.localizedDescription ?? "The encoder stopped.")
                }
                try await Task.sleep(for: .milliseconds(2))
            }
        }
        writer.endSession(atSourceTime: duration.cmTime)
        progress(ExportProgress(phase: .finishing, fraction: 0.95))
        await writer.finishWriting()
        try Task.checkCancellation()
        guard writer.status == .completed else { throw VideoError.renderingFailed(writer.error?.localizedDescription ?? "The encoder did not finish.") }
        complete = true
    }

    private func mixAudio(clips: [MediaClip], sources: [UUID: AppleAudioSource], startFrame: Int64, count: Int) throws -> [Float] {
        var result = [Float](repeating: 0, count: count * 2)
        let rate = Double(AppleAudioSource.sampleRate)
        for clip in clips {
            guard let source = sources[clip.id] else { continue }
            let clipStart = clip.start.seconds
            let end = try clip.timeRange.end.seconds
            let left = sqrt((1 - clip.audio.pan) / 2) * sqrt(2.0)
            let right = sqrt((1 + clip.audio.pan) / 2) * sqrt(2.0)
            for index in 0..<count {
                let time = Double(startFrame + Int64(index)) / rate
                guard time >= clipStart && time < end else { continue }
                let sourceFrame = Int64(((time - clipStart + clip.sourceStart.seconds) * rate).rounded())
                let pair = try source.sample(at: sourceFrame)
                let effectTime = time - clipStart + clip.effectsOffset.seconds
                let gain = clip.audio.gain(atSeconds: effectTime, durationSeconds: clip.effectsDuration.seconds)
                result[index * 2] += pair.0 * Float(gain * left)
                result[index * 2 + 1] += pair.1 * Float(gain * right)
            }
        }
        // Explicit hard limiting after summation prevents integer conversion or encoder clipping surprises.
        return result.map { min(1, max(-1, $0)) }
    }

    private func makeAudioBuffer(_ samples: [Float], startFrame: Int64) throws -> CMSampleBuffer {
        var description = AudioStreamBasicDescription(mSampleRate: Double(AppleAudioSource.sampleRate), mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, mBytesPerPacket: 8, mFramesPerPacket: 1,
            mBytesPerFrame: 8, mChannelsPerFrame: 2, mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(allocator: kCFAllocatorDefault, asbd: &description, layoutSize: 0,
            layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format)
        guard formatStatus == noErr, let format else { throw VideoError.renderingFailed("Cannot create PCM format.") }
        var block: CMBlockBuffer?
        let bytes = samples.count * MemoryLayout<Float>.size
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes,
            blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0, dataLength: bytes, flags: 0, blockBufferOut: &block)
        guard blockStatus == kCMBlockBufferNoErr, let block else { throw VideoError.renderingFailed("Cannot allocate PCM output.") }
        let copyStatus = samples.withUnsafeBytes { pointer in
            // Nonempty PCM blocks always have a base address.
            CMBlockBufferReplaceDataBytes(with: pointer.baseAddress!, blockBuffer: block, offsetIntoDestination: 0, dataLength: bytes)
        }
        guard copyStatus == noErr else { throw VideoError.renderingFailed("Cannot copy PCM output.") }
        var buffer: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: AppleAudioSource.sampleRate),
            presentationTimeStamp: CMTime(value: startFrame, timescale: AppleAudioSource.sampleRate), decodeTimeStamp: .invalid)
        var sampleSize = 8
        let status = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
            sampleCount: samples.count / 2, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
            sampleSizeEntryCount: 1, sampleSizeArray: &sampleSize, sampleBufferOut: &buffer)
        guard status == noErr, let buffer else { throw VideoError.renderingFailed("Cannot create encoded audio input (\(status)).") }
        return buffer
    }
}

extension VideoExporter {
    public init() { self.init(renderer: AppleVideoRenderer()) }
}
#endif
