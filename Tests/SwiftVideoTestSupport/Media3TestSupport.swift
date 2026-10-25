// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.media.MediaMetadataRetriever
import android.media.MediaExtractor
import android.media.MediaCodec
import android.media.MediaFormat
import android.graphics.Color
import java.io.File
import java.io.FileOutputStream
#endif

/// Integration fixtures and independent Android output inspection, linked only by tests.
public final class Media3TestSupport {
    public static func copyFixture(name: String) throws -> String {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        let file = File(context.getCacheDir(), name)
        let input = context.getAssets().open("swift/video/Resources/Milestone/" + name)
        defer { input.close() }
        let output = FileOutputStream(file)
        defer { output.close() }
        let buffer = kotlin.ByteArray(8192)
        while true {
            let count = input.read(buffer)
            if count < 0 { break }
            output.write(buffer, 0, count)
        }
        return file.getAbsolutePath()
        #else
        throw unavailable()
        #endif
    }

    public static func frameStats(path: String, timeUs: Int64) throws -> [Double] {
        #if SKIP
        let retriever = MediaMetadataRetriever()
        defer { retriever.release() }
        retriever.setDataSource(path)
        guard let bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST) else {
            throw IllegalStateException("Cannot decode exported frame.")
        }
        defer { bitmap.recycle() }
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let center = bitmap.getPixel(width / 2, Int(Double(height) * 0.5556))
        let overlay = bitmap.getPixel(Int(Double(width) * 0.85), Int(Double(height) * 0.8))
        var sum = 0.0
        var count = 0
        for y in 0..<height {
            for x in 0..<width {
                let color = bitmap.getPixel(x, y)
                if Color.red(color) > 200 && Color.green(color) > 200 && Color.blue(color) > 200 { sum += Double(x); count += 1 }
            }
        }
        let duration = Double(retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION) ?? "0") ?? 0.0
        return [Double(width), Double(height), duration, Double(Color.red(center)), Double(Color.green(center)), Double(Color.blue(center)),
                Double(Color.red(overlay)), Double(Color.green(overlay)), Double(Color.blue(overlay)), count == 0 ? -1.0 : sum / Double(count)]
        #else
        throw unavailable()
        #endif
    }

    public static func audioRMS(path: String) throws -> [Double] {
        #if SKIP
        let extractor = MediaExtractor()
        defer { extractor.release() }
        extractor.setDataSource(path)
        var selected: MediaFormat? = nil
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME) ?? "").hasPrefix("audio/") {
                selected = format
                extractor.selectTrack(index)
                break
            }
        }
        guard let format = selected, let mime = format.getString(MediaFormat.KEY_MIME) else {
            throw IllegalStateException("Export has no audio track.")
        }
        let decoder = MediaCodec.createDecoderByType(mime)
        defer { decoder.stop(); decoder.release() }
        decoder.configure(format, nil, nil, 0)
        decoder.start()
        var inputEnded = false
        var outputEnded = false
        var squares = [0.0, 0.0, 0.0]
        var counts = [0, 0, 0]
        let info = MediaCodec.BufferInfo()
        let deadline = java.lang.System.nanoTime() + Int64(30_000_000_000)
        var sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        var channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        var pcm = 2
        while !outputEnded {
            if java.lang.System.nanoTime() > deadline { throw IllegalStateException("Audio inspection timed out.") }
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
                }
            }
            let index = decoder.dequeueOutputBuffer(info, Int64(10_000))
            if index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED {
                let output = decoder.getOutputFormat()
                sampleRate = output.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                channels = output.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                pcm = output.containsKey(MediaFormat.KEY_PCM_ENCODING) ? output.getInteger(MediaFormat.KEY_PCM_ENCODING) : 2
            } else if index >= 0 {
                if let buffer = decoder.getOutputBuffer(index), info.size > 0 {
                    buffer.position(info.offset)
                    buffer.limit(info.offset + info.size)
                    buffer.order(java.nio.ByteOrder.nativeOrder())
                    let frameBytes = channels * (pcm == 4 ? 4 : 2)
                    let frameCount = info.size / frameBytes
                    for frame in 0..<frameCount {
                        let sample = pcm == 4 ? Double(buffer.getFloat()) : Double(buffer.getShort()) / 32768
                        for _ in 1..<channels { if pcm == 4 { buffer.getFloat() } else { buffer.getShort() } }
                        let time = Double(info.presentationTimeUs) / 1_000_000 + Double(frame) / Double(sampleRate)
                        let slot = time < 0.05 ? 0 : ((time >= 0.5 && time < 0.55) ? 1 : ((time >= 1.9375 && time < 1.9875) ? 2 : -1))
                        if slot >= 0 { squares[slot] += sample * sample; counts[slot] += 1 }
                    }
                }
                outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                decoder.releaseOutputBuffer(index, false)
            }
        }
        return (0..<3).map { counts[$0] == 0 ? -1.0 : sqrt(squares[$0] / Double(counts[$0])) }
        #else
        throw unavailable()
        #endif
    }

    #if !SKIP
    private static func unavailable() -> NSError {
        NSError(domain: "SwiftVideoMedia3", code: 1, userInfo: [NSLocalizedDescriptionKey: "Android test support requires an Android runtime."])
    }
    #endif
}
#endif
