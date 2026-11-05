// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import SwiftVideoMedia3
import androidx.media3.common.__
import androidx.media3.common.util.ParsableByteArray
import androidx.media3.extractor.TrackOutput
#endif

public final class PcmBoundaryProbe {
    public static func segments(cuts: [Int64], compressed: Bool) -> [Int64] {
        #if SKIP
        let recording = RecordingPacketOutput()
        let track = BoundaryTrackOutput(recording, boundaries: cuts)
        track.format(Format.Builder().setSampleMimeType(compressed ? MimeTypes.AUDIO_AAC : MimeTypes.AUDIO_RAW)
            .setSampleRate(1000).setChannelCount(2).setPcmEncoding(C.ENCODING_PCM_16BIT).build())
        // 100 stereo PCM frames, with eight subsequent bytes already buffered.
        track.sampleMetadata(200_000, C.BUFFER_FLAG_KEY_FRAME | C.BUFFER_FLAG_LAST_SAMPLE, 400, 8, nil)
        return recording.segments
        #else
        return []
        #endif
    }
}

#if SKIP
private final class RecordingPacketOutput: TrackOutput {
    var segments: [Int64] = []
    override func format(format: Format) {}
    override func sampleData(input: DataReader, length: Int, allowEndOfInput: Bool, sampleDataPart: Int) -> Int { 0 }
    override func sampleData(data: ParsableByteArray, length: Int, sampleDataPart: Int) {}
    override func sampleMetadata(timeUs: Int64, flags: Int, size: Int, offset: Int, cryptoData: TrackOutput.CryptoData?) {
        segments.append(contentsOf: [timeUs, Int64(size), Int64(offset), (flags & C.BUFFER_FLAG_LAST_SAMPLE) == 0 ? 0 : 1])
    }
}
#endif
#endif
