// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.net.Uri
import androidx.media3.common.__
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.common.util.Util
import androidx.media3.extractor.__

/// Splits PCM packet metadata at known cuts before SampleQueue can discard a
/// packet crossing the requested start. Sample bytes pass through unchanged.
// SKIP @nobridge
public final class PcmBoundaryExtractorsFactory: ExtractorsFactory {
    private let boundaries: [String: [Int64]]
    private let factory = DefaultExtractorsFactory()

    public init(boundaries: [String: [Int64]]) { self.boundaries = boundaries }

    override func createExtractors() -> kotlin.Array<Extractor> { factory.createExtractors() }

    override func createExtractors(uri: Uri, responseHeaders: kotlin.collections.Map<String, kotlin.collections.List<String>>) -> kotlin.Array<Extractor> {
        let extractors = factory.createExtractors(uri, responseHeaders)
        guard let points = boundaries[uri.toString()], !points.isEmpty else { return extractors }
        return kotlin.Array(extractors.size) { index in BoundaryExtractor(extractors[index], boundaries: points) }
    }
}

private final class BoundaryExtractor: Extractor {
    // Skip interprets a direct .init call as a Swift constructor. Resolve the
    // public Java method once; it runs only when the extractor is initialized.
    private static let initialize = java.lang.Class.forName("androidx.media3.extractor.Extractor")
        .getMethod("init", java.lang.Class.forName("androidx.media3.extractor.ExtractorOutput"))
    private let extractor: Extractor
    private let boundaries: [Int64]
    init(_ extractor: Extractor, boundaries: [Int64]) { self.extractor = extractor; self.boundaries = boundaries }
    override func sniff(input: ExtractorInput) -> Bool { extractor.sniff(input) }
    override func `init`(output: ExtractorOutput) {
        Self.initialize.invoke(extractor, BoundaryExtractorOutput(output, boundaries: boundaries))
        return
    }
    override func read(input: ExtractorInput, seekPosition: PositionHolder) -> Int { extractor.read(input, seekPosition) }
    override func seek(position: Int64, timeUs: Int64) { extractor.seek(position, timeUs) }
    override func release() { extractor.release() }
    override func getUnderlyingImplementation() -> Extractor { extractor.getUnderlyingImplementation() }
}

private final class BoundaryExtractorOutput: ExtractorOutput {
    private let output: ExtractorOutput
    private let boundaries: [Int64]
    init(_ output: ExtractorOutput, boundaries: [Int64]) { self.output = output; self.boundaries = boundaries }
    override func track(id: Int, type: Int) -> TrackOutput {
        let track = output.track(id, type)
        return type == C.TRACK_TYPE_AUDIO ? BoundaryTrackOutput(track, boundaries: boundaries) : track
    }
    override func endTracks() { output.endTracks() }
    override func seekMap(seekMap: SeekMap) { output.seekMap(seekMap) }
}

// SKIP @nobridge
public final class BoundaryTrackOutput: TrackOutput {
    private let output: TrackOutput
    private let boundaries: [Int64]
    private var frameBytes = 0
    private var sampleRate = 0
    public init(_ output: TrackOutput, boundaries: [Int64]) { self.output = output; self.boundaries = boundaries }
    override func durationUs(durationUs: Int64) { output.durationUs(durationUs) }
    override func format(format: Format) {
        frameBytes = format.sampleMimeType == MimeTypes.AUDIO_RAW && Util.isEncodingLinearPcm(format.pcmEncoding)
            ? Util.getPcmFrameSize(format.pcmEncoding, format.channelCount) : 0
        sampleRate = format.sampleRate
        output.format(format)
    }
    override func sampleData(input: DataReader, length: Int, allowEndOfInput: Bool, sampleDataPart: Int) -> Int {
        output.sampleData(input, length, allowEndOfInput, sampleDataPart)
    }
    override func sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {
        output.sampleData(data, length, sampleDataPart)
    }
    override func sampleMetadata(timeUs: Int64, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
        guard frameBytes > 0, sampleRate > 0, size > 0, size % frameBytes == 0, cryptoData == nil else {
            output.sampleMetadata(timeUs, flags, size, offset, cryptoData)
            return
        }
        let frames = Int64(size / frameBytes)
        var previous: Int64 = 0
        for boundary in boundaries where boundary > timeUs {
            let delta = boundary - timeUs
            if delta >= (frames * 1_000_000 + Int64(sampleRate) - 1) / Int64(sampleRate) { break }
            let frame = min(frames, (delta * Int64(sampleRate) + 999_999) / 1_000_000)
            if frame == frames { break }
            if frame <= previous { continue }
            let bytes = Int(frame - previous) * frameBytes
            output.sampleMetadata(timeUs + previous * 1_000_000 / Int64(sampleRate), flags & ~C.BUFFER_FLAG_LAST_SAMPLE,
                                  bytes, offset + size - Int(frame) * frameBytes, nil)
            previous = frame
        }
        if previous < frames {
            output.sampleMetadata(timeUs + previous * 1_000_000 / Int64(sampleRate), flags,
                                  Int(frames - previous) * frameBytes, offset, nil)
        }
    }
}
#endif
