// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.media.AudioFormat
import android.media.MediaExtractor
import android.media.MediaFormat
import android.net.Uri
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import org.json.JSONObject

/// Materializes only selected PCM ranges. Media3's WAV packet clipping can start
/// at different packet boundaries across otherwise identical exports.
/// Run off the application looper; each file belongs to the export scratch folder.
final class Media3PCMTrimmer {
    func prepare(_ original: JSONObject, folder: File, cancelled: () -> Bool) throws -> JSONObject {
        let plan = JSONObject(original.toString())
        let clips = plan.getJSONArray("clips")
        var cached: [String: String] = [:]
        for index in 0..<clips.length() {
            try checkCancellation(cancelled)
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            let start = clip.getLong("sourceStartUs")
            if (kind != "audio" && kind != "video") || clip.getBoolean("muted") || start == Int64(0) { continue }
            let source = clip.getString("url")
            let duration = clip.getLong("sourceDurationUs")
            let key = source + "\n" + String(start) + ":" + String(duration)
            let prepared: String
            if let previous = cached[key] { prepared = previous }
            else {
                prepared = try trim(source: source, startUs: start, durationUs: duration, folder: folder,
                                    cancelled: cancelled) ?? source
                cached[key] = prepared
            }
            if prepared != source {
                clip.put("audioURL", prepared)
                clip.put("audioSourceStartUs", Int64(0))
            }
        }
        return plan
    }

    private func trim(source: String, startUs: Int64, durationUs: Int64, folder: File,
                      cancelled: () -> Bool) throws -> String? {
        let extractor = MediaExtractor()
        defer { extractor.release() }
        extractor.setDataSource(ProcessInfo.processInfo.androidContext, Uri.parse(source), nil)
        var selected: MediaFormat?
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME) ?? "").hasPrefix("audio/") {
                guard format.getString(MediaFormat.KEY_MIME) == "audio/raw" else { return nil }
                selected = format
                extractor.selectTrack(index)
                break
            }
        }
        guard let format = selected else { return nil }
        let encoding = format.containsKey(MediaFormat.KEY_PCM_ENCODING)
            ? format.getInteger(MediaFormat.KEY_PCM_ENCODING) : AudioFormat.ENCODING_PCM_16BIT
        guard encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT else { return nil }
        let rate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        let channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        let bits = encoding == AudioFormat.ENCODING_PCM_FLOAT ? 32 : 16
        let frameBytes = channels * bits / 8
        guard startUs >= 0, durationUs > 0, rate > 0, channels >= 1, channels <= 2 else {
            throw IllegalArgumentException("Invalid PCM source range or format")
        }
        // Quantize to PCM frames and retain enough frames for the requested duration.
        let startFrame = java.lang.Math.multiplyExact(startUs, Int64(rate)) / 1_000_000
        let frames = java.lang.Math.addExact(java.lang.Math.multiplyExact(durationUs, Int64(rate)), Int64(999_999)) / 1_000_000
        let bytes = java.lang.Math.multiplyExact(frames, Int64(frameBytes))
        guard bytes <= 4_294_967_259, bytes <= folder.getUsableSpace() - 1_048_576 else {
            throw IllegalArgumentException("Selected PCM audio exceeds available WAV storage")
        }
        try checkCancellation(cancelled)
        extractor.seekTo(startUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        let file = File(folder, "pcm-" + UUID().uuidString + ".wav")
        var complete = false
        defer { if !complete { file.delete() } }
        let output = RandomAccessFile(file, "rw")
        defer { output.close() }
        output.write(kotlin.ByteArray(44))
        let transfer = kotlin.ByteArray(32 * 1024)
        var buffer = ByteBuffer.allocateDirect(32 * 1024)
        var written: Int64 = 0
        while written < frames && extractor.getSampleTime() >= 0 {
            try checkCancellation(cancelled)
            let size = extractor.getSampleSize()
            guard size >= 0, size <= 1_048_576 else { throw IllegalArgumentException("Unsupported PCM packet size") }
            if size > Int64(buffer.capacity()) { buffer = ByteBuffer.allocateDirect(Int(size)) }
            buffer.clear()
            let count = extractor.readSampleData(buffer, 0)
            guard count >= 0, count % frameBytes == 0 else { throw IllegalArgumentException("Incomplete PCM packet") }
            let packetFrame = java.lang.Math.addExact(java.lang.Math.multiplyExact(extractor.getSampleTime(), Int64(rate)), Int64(500_000)) / 1_000_000
            let position = packetFrame - startFrame
            let packetFrames = Int64(count / frameBytes)
            let skip = min(packetFrames, max(Int64(0), written - position))
            if skip < packetFrames {
                var gapBytes = min(frames - written, max(Int64(0), position - written)) * Int64(frameBytes)
                if gapBytes > 0 {
                    java.util.Arrays.fill(transfer, Int8(0))
                    written += gapBytes / Int64(frameBytes)
                    while gapBytes > 0 {
                        try checkCancellation(cancelled)
                        let chunk = Int(min(gapBytes, Int64(transfer.size)))
                        output.write(transfer, 0, chunk)
                        gapBytes -= Int64(chunk)
                    }
                }
                let retained = min(frames - written, packetFrames - skip)
                buffer.position(Int(skip) * frameBytes)
                buffer.limit(Int(skip + retained) * frameBytes)
                while buffer.hasRemaining() {
                    try checkCancellation(cancelled)
                    let chunk = min(buffer.remaining(), transfer.size)
                    buffer.get(transfer, 0, chunk)
                    output.write(transfer, 0, chunk)
                }
                written += retained
            }
            extractor.advance()
        }
        guard written == frames else { throw IllegalArgumentException("PCM source range exceeds available samples") }
        try checkCancellation(cancelled)
        output.seek(0)
        output.writeBytes("RIFF")
        output.writeInt(java.lang.Integer.reverseBytes(Int(bytes + 36)))
        output.writeBytes("WAVEfmt ")
        output.writeInt(java.lang.Integer.reverseBytes(16))
        output.writeShort(Int(java.lang.Short.reverseBytes(Int16(bits == 32 ? 3 : 1))))
        output.writeShort(Int(java.lang.Short.reverseBytes(Int16(channels))))
        output.writeInt(java.lang.Integer.reverseBytes(rate))
        output.writeInt(java.lang.Integer.reverseBytes(rate * frameBytes))
        output.writeShort(Int(java.lang.Short.reverseBytes(Int16(frameBytes))))
        output.writeShort(Int(java.lang.Short.reverseBytes(Int16(bits))))
        output.writeBytes("data")
        output.writeInt(java.lang.Integer.reverseBytes(Int(bytes)))
        complete = true
        return Uri.fromFile(file).toString()
    }

    private func checkCancellation(_ cancelled: () -> Bool) throws {
        if cancelled() { throw java.util.concurrent.CancellationException("PCM preparation cancelled") }
    }
}
#endif
