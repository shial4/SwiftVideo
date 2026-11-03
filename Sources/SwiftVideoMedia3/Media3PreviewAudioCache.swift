// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaFormat
import androidx.media3.inspector.MediaExtractorCompat
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.media3.extractor.mp4.Mp4Extractor
import android.net.Uri
import android.os.SystemClock
import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import org.json.JSONObject

/// Session-owned decoded audio, reusable across player recreation and seeking.
/// Call off the application looper and keep the folder until all players release.
// SKIP @nobridge
public final class Media3PreviewAudioCache {
    private let folder: File
    private let maximumBytes: Int64
    private var usedBytes: Int64 = 0
    private var sources: [String: String] = [:]

    public init(folder: File, maximumBytes: Int64 = 64 * 1024 * 1024) {
        self.folder = folder
        self.maximumBytes = maximumBytes
    }

    public func prepare(_ original: JSONObject, cancelled: () -> Bool) throws -> JSONObject {
        guard maximumBytes >= 44, maximumBytes <= 2_147_483_647 else {
            throw IllegalArgumentException("Invalid decoded preview audio cache limit")
        }
        let plan = JSONObject(original.toString())
        let clips = plan.getJSONArray("clips")
        for index in 0..<clips.length() {
            try checkCancellation(cancelled)
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            if (kind != "audio" && kind != "video") || clip.getBoolean("muted") { continue }
            let source = clip.getString("url")
            let prepared: String
            if let cached = sources[source] { prepared = cached }
            else {
                prepared = try decode(source, cancelled: cancelled)
                sources[source] = prepared
            }
            if prepared != source { clip.put("audioURL", prepared) }
        }
        return plan
    }

    private func decode(_ source: String, cancelled: () -> Bool) throws -> String {
        let context = ProcessInfo.processInfo.androidContext
        var extractor = MediaExtractorCompat(context)
        defer { extractor.release() }
        extractor.setDataSource(ProcessInfo.processInfo.androidContext, Uri.parse(source), nil)
        var selected: MediaFormat?
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME) ?? "").hasPrefix("audio/") {
                selected = format
                extractor.selectTrack(index)
                break
            }
        }
        guard let format = selected, let mime = format.getString(MediaFormat.KEY_MIME), mime != "audio/raw" else { return source }
        let trackID = format.containsKey(MediaFormat.KEY_TRACK_ID) ? format.getInteger(MediaFormat.KEY_TRACK_ID) : -1
        let profile = format.containsKey(MediaFormat.KEY_PROFILE) ? format.getInteger(MediaFormat.KEY_PROFILE) : -1
        let legacy = mime == "audio/mp4a-latm" ? Media3AACPriming.inspect(source: source, trackID: trackID,
            sampleRate: format.getInteger(MediaFormat.KEY_SAMPLE_RATE), profile: profile) : nil
        if let legacy {
            // Preserve AAC preroll packets; apply the recognized legacy edit once,
            // after decoding. Media3's regular edit handling can discard them.
            extractor.release()
            extractor = MediaExtractorCompat(DefaultExtractorsFactory().setMp4ExtractorFlags(Mp4Extractor.FLAG_WORKAROUND_IGNORE_EDIT_LISTS),
                                              DefaultDataSource.Factory(context))
            extractor.setDataSource(context, Uri.parse(source), nil)
            var found = false
            for index in 0..<extractor.getTrackCount() {
                let track = extractor.getTrackFormat(index)
                if track.containsKey(MediaFormat.KEY_TRACK_ID), track.getInteger(MediaFormat.KEY_TRACK_ID) == trackID {
                    extractor.selectTrack(index); found = true; break
                }
            }
            guard found else { throw IllegalStateException("Missing source audio track") }
            format.setInteger(MediaFormat.KEY_ENCODER_DELAY, legacy.delayFrames)
            format.setInteger(MediaFormat.KEY_ENCODER_PADDING, legacy.paddingFrames)
        }
        let sourceStartUs = legacy?.startUs ?? extractor.getSampleTime()
        let sourceDurationUs = legacy?.endUs ?? (format.containsKey(MediaFormat.KEY_DURATION) ? format.getLong(MediaFormat.KEY_DURATION) : Int64(-1))
        try checkCancellation(cancelled)
        let file = File(folder, "audio-" + UUID().uuidString + ".wav")
        let partial = File(file.getPath() + ".partial")
        var completed = false
        defer { if !completed { partial.delete(); file.delete() } }
        let output = RandomAccessFile(partial, "rw")
        defer { output.close() }
        output.write(kotlin.ByteArray(44))
        let decoder = MediaCodec.createDecoderByType(mime)
        defer { decoder.release() }
        format.setInteger(MediaFormat.KEY_PCM_ENCODING, AudioFormat.ENCODING_PCM_16BIT)
        decoder.configure(format, nil, nil, 0)
        decoder.start()
        defer { decoder.stop() }
        let info = MediaCodec.BufferInfo()
        let transfer = kotlin.ByteArray(32 * 1024)
        var inputEnded = false
        var outputEnded = false
        var sampleRate = 0
        var channels = 0
        var encoding = AudioFormat.ENCODING_PCM_16BIT
        var framesWritten: Int64 = 0
        var decodedFrames: Int64 = 0
        var sourceEndFrame = Double.infinity
        var lastProgress = SystemClock.elapsedRealtime()
        while !outputEnded {
            try checkCancellation(cancelled)
            guard SystemClock.elapsedRealtime() - lastProgress < 30_000 else {
                throw IllegalStateException("Audio decoder stopped making progress")
            }
            if !inputEnded {
                let index = decoder.dequeueInputBuffer(Int64(10_000))
                if index >= 0, let buffer = decoder.getInputBuffer(index) {
                    let size = extractor.readSampleData(buffer, 0)
                    if size < 0 {
                        decoder.queueInputBuffer(index, 0, 0, Int64(0), MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        inputEnded = true
                    } else {
                        decoder.queueInputBuffer(index, 0, size, extractor.getSampleTime(), 0)
                        extractor.advance()
                    }
                    lastProgress = SystemClock.elapsedRealtime()
                }
            }
            let index = decoder.dequeueOutputBuffer(info, Int64(10_000))
            if index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED {
                let decoded = decoder.getOutputFormat()
                let nextRate = decoded.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                let nextChannels = decoded.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                guard nextRate > 0, nextChannels >= 1, nextChannels <= 2,
                      sampleRate == 0 || (nextRate == sampleRate && nextChannels == channels) else {
                    throw IllegalArgumentException("Preview audio requires a constant mono or stereo format")
                }
                sampleRate = nextRate
                channels = nextChannels
                if sourceDurationUs > 0 {
                    sourceEndFrame = ceil(Double(sourceDurationUs) * Double(sampleRate) / 1_000_000)
                }
                encoding = decoded.containsKey(MediaFormat.KEY_PCM_ENCODING)
                    ? decoded.getInteger(MediaFormat.KEY_PCM_ENCODING) : AudioFormat.ENCODING_PCM_16BIT
                guard encoding == AudioFormat.ENCODING_PCM_16BIT || encoding == AudioFormat.ENCODING_PCM_FLOAT else {
                    throw IllegalArgumentException("Unsupported decoded preview PCM encoding")
                }
                lastProgress = SystemClock.elapsedRealtime()
            } else if index >= 0 {
                defer { decoder.releaseOutputBuffer(index, false) }
                if let buffer = decoder.getOutputBuffer(index), info.size > 0 {
                    guard sampleRate > 0, channels > 0 else { throw IllegalStateException("Missing decoded audio format") }
                    let inputFrameBytes = channels * (encoding == AudioFormat.ENCODING_PCM_FLOAT ? 4 : 2)
                    guard info.size % inputFrameBytes == 0 else { throw IllegalStateException("Incomplete decoded audio frame") }
                    let count = Int64(info.size / inputFrameBytes)
                    // Codec timestamps still describe encoded packets after decoder
                    // priming is removed. Keep contiguous decoded samples together,
                    // anchored to the source track's actual starting timestamp.
                    let availableFrames = (maximumBytes - usedBytes - 44) / Int64(channels * 2)
                    let timestamp = (Double(sourceStartUs) * Double(sampleRate) / 1_000_000).rounded() + Double(decodedFrames)
                    guard timestamp <= Double(availableFrames) else {
                        throw IllegalStateException("Decoded preview audio exceeds the cache size limit")
                    }
                    let start = Int64(max(-Double(count), timestamp))
                    let skip = min(count, max(Int64(0), framesWritten - start))
                    decodedFrames += count
                    if skip < count {
                        let gap = Int64(min(Double(max(Int64(0), start - framesWritten)),
                                            max(0.0, sourceEndFrame - Double(framesWritten))))
                        // An MP4 edit can end inside its last AAC access unit.
                        // Keep only the decoded frames inside the source timeline.
                        let retained = Int64(min(Double(count - skip),
                            max(0.0, sourceEndFrame - Double(framesWritten) - Double(gap))))
                        guard framesWritten <= availableFrames, gap <= availableFrames - framesWritten,
                              retained <= availableFrames - framesWritten - gap else {
                            throw IllegalStateException("Decoded preview audio exceeds the cache size limit")
                        }
                        var silence = gap * Int64(channels * 2)
                        if silence > 0 {
                            java.util.Arrays.fill(transfer, Int8(0))
                            while silence > 0 {
                                try checkCancellation(cancelled)
                                let size = Int(min(silence, Int64(transfer.size)))
                                output.write(transfer, 0, size)
                                silence -= Int64(size)
                            }
                        }
                        buffer.position(info.offset + Int(skip) * inputFrameBytes)
                        buffer.limit(info.offset + Int(skip + retained) * inputFrameBytes)
                        buffer.order(ByteOrder.LITTLE_ENDIAN)
                        if encoding == AudioFormat.ENCODING_PCM_16BIT {
                            while buffer.hasRemaining() {
                                let size = min(buffer.remaining(), transfer.size)
                                buffer.get(transfer, 0, size)
                                output.write(transfer, 0, size)
                            }
                        } else {
                            let converted = ByteBuffer.wrap(transfer).order(ByteOrder.LITTLE_ENDIAN)
                            while buffer.hasRemaining() {
                                converted.clear()
                                while buffer.hasRemaining() && converted.remaining() >= 2 {
                                    let value = Double(buffer.getFloat())
                                    converted.putShort(Int16(value.isFinite ? max(-32768.0, min(32767.0, value * 32768)) : 0.0))
                                }
                                output.write(transfer, 0, converted.position())
                            }
                        }
                        framesWritten += gap + retained
                    }
                }
                outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 || Double(framesWritten) >= sourceEndFrame
                lastProgress = SystemClock.elapsedRealtime()
            }
        }
        try checkCancellation(cancelled)
        guard sampleRate > 0, framesWritten > 0 else { throw IllegalStateException("Audio decoder produced no samples") }
        let bytes = framesWritten * Int64(channels * 2)
        let header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.putInt(0x46464952); header.putInt(Int(bytes + 36)); header.putInt(0x45564157)
        header.putInt(0x20746D66); header.putInt(16); header.putShort(Int16(1)); header.putShort(Int16(channels))
        header.putInt(sampleRate); header.putInt(sampleRate * channels * 2)
        header.putShort(Int16(channels * 2)); header.putShort(Int16(16))
        header.putInt(0x61746164); header.putInt(Int(bytes))
        output.seek(Int64(0))
        output.write(header.array())
        output.getFD().sync()
        output.close()
        guard partial.renameTo(file) else { throw IllegalStateException("Cannot publish decoded preview audio") }
        usedBytes += bytes + 44
        completed = true
        return Uri.fromFile(file).toString()
    }

    private func checkCancellation(_ cancelled: () -> Bool) throws {
        if cancelled() { throw java.util.concurrent.CancellationException("Preview audio preparation cancelled") }
    }
}
#endif
