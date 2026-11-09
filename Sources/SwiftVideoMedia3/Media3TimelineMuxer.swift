// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.Metadata
import androidx.media3.common.MimeTypes
import androidx.media3.muxer.BufferInfo
import androidx.media3.muxer.Muxer
import androidx.media3.transformer.InAppMp4Muxer
import com.google.common.collect.ImmutableList
import java.nio.ByteBuffer

/// Keeps the timeline endpoint without sending EOS to an unwritten video track.
/// Media3 1.11.1's duration-configured InAppMp4Muxer can crash on early cancellation:
/// Mp4Writer tries to update a moov box before its reserved space exists.
final class TimelineMuxerFactory: Muxer.Factory {
    private let durationUs: Int64
    private let factory = InAppMp4Muxer.Factory()
    init(durationUs: Int64) { self.durationUs = durationUs }

    override func create(path: String) -> Muxer {
        TimelineMuxer(delegate: factory.create(path), durationUs: durationUs)
    }
    override func getSupportedSampleMimeTypes(trackType: Int) -> ImmutableList<String> {
        factory.getSupportedSampleMimeTypes(trackType)
    }
    override func supportsWritingNegativeTimestampsInEditList() -> Bool {
        factory.supportsWritingNegativeTimestampsInEditList()
    }
}

private final class TimelineMuxer: Muxer {
    private let delegate: Muxer
    private let durationUs: Int64
    private var videoTrack = -1
    private var videoStarted = false

    init(delegate: Muxer, durationUs: Int64) { self.delegate = delegate; self.durationUs = durationUs }

    override func addTrack(format: Format) -> Int {
        let id = delegate.addTrack(format)
        if MimeTypes.isVideo(format.sampleMimeType) { videoTrack = id }
        return id
    }

    override func writeSampleData(trackId: Int, byteBuffer: ByteBuffer, bufferInfo: BufferInfo) {
        if trackId == videoTrack && bufferInfo.presentationTimeUs > durationUs { return }
        let startsVideo = trackId == videoTrack && bufferInfo.size > 0 && byteBuffer.hasRemaining()
            && (bufferInfo.flags & C.BUFFER_FLAG_KEY_FRAME) != 0
        delegate.writeSampleData(trackId, byteBuffer, bufferInfo)
        if startsVideo { videoStarted = true }
    }

    override func addMetadataEntry(metadataEntry: Metadata.Entry) { delegate.addMetadataEntry(metadataEntry) }

    override func close() {
        defer { delegate.close() }
        if videoStarted {
            delegate.writeSampleData(videoTrack, ByteBuffer.allocateDirect(0), BufferInfo(durationUs, 0, C.BUFFER_FLAG_END_OF_STREAM))
        }
    }
}
#endif
