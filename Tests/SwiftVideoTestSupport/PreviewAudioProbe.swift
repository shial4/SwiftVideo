// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import androidx.media3.common.C
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.atomic.AtomicLongArray

/// Reads only PCM accepted by the real audio sink, including partial writes.
final class PreviewAudioProbe: ForwardingAudioSink {
    private let counts: AtomicLongArray
    private let squares: AtomicLongArray
    private var sampleRate = 0
    private var channels = 0
    private var bytesPerSample = 0

    init(sink: AudioSink, counts: AtomicLongArray, squares: AtomicLongArray) {
        self.counts = counts
        self.squares = squares
        super.init(sink)
    }

    override func configure(audioSinkConfig: AudioSink.AudioSinkConfig) {
        let format = audioSinkConfig.format
        sampleRate = format.sampleRate
        channels = format.channelCount
        if format.pcmEncoding == C.ENCODING_PCM_16BIT { bytesPerSample = 2 }
        else if format.pcmEncoding == C.ENCODING_PCM_FLOAT { bytesPerSample = 4 }
        else { throw IllegalStateException("Unsupported preview probe PCM encoding: " + String(format.pcmEncoding)) }
        super.configure(audioSinkConfig)
    }

    override func handleBuffer(buffer: ByteBuffer, presentationTimeUs: Int64, encodedAccessUnitCount: Int) -> Bool {
        let start = buffer.position()
        let handled = super.handleBuffer(buffer, presentationTimeUs, encodedAccessUnitCount)
        let end = buffer.position()
        let frameBytes = channels * bytesPerSample
        guard frameBytes > 0, sampleRate > 0 else { return handled }
        let samples = buffer.duplicate().order(ByteOrder.nativeOrder())
        // CompositionPlayer advances the timestamp after each partial write.
        // It refers to the current buffer position, not its original position.
        var offset = start
        while offset + frameBytes <= end {
            let timeUs = presentationTimeUs + Int64(offset - start) / Int64(frameBytes) * 1_000_000 / Int64(sampleRate)
            let slot = timeUs >= 500_000 && timeUs < 550_000 ? 0 :
                (timeUs >= 1_000_000 && timeUs < 1_050_000 ? 1 :
                    (timeUs >= 1_937_500 && timeUs < 1_987_500 ? 2 : -1))
            if slot >= 0 {
                let value = bytesPerSample == 2 ? Int64(samples.getShort(offset)) : Int64(Double(samples.getFloat(offset)) * 32768)
                counts.incrementAndGet(slot)
                squares.addAndGet(slot, value * value)
            }
            offset += frameBytes
        }
        return handled
    }
}
#endif
