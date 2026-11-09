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
    /// Exercise the actual internal factory without adding test APIs to the library bridge.
    public static func closeEmptyTimelineMuxer(path: String, durationUs: Int64) throws {
        #if SKIP
        let type = java.lang.Class.forName("swift.video.media3.TimelineMuxerFactory")
        let constructor = type.getDeclaredConstructor(java.lang.Long.TYPE)
        constructor.setAccessible(true)
        let factory = constructor.newInstance(durationUs)
        let factoryType = java.lang.Class.forName("androidx.media3.muxer.Muxer$Factory")
        let muxer = factoryType.getMethod("create", java.lang.Class.forName("java.lang.String")).invoke(factory, path)
        let builderType = java.lang.Class.forName("androidx.media3.common.Format$Builder")
        let builder = builderType.getDeclaredConstructor().newInstance()
        builderType.getMethod("setSampleMimeType", java.lang.Class.forName("java.lang.String")).invoke(builder, "video/avc")
        builderType.getMethod("setWidth", java.lang.Integer.TYPE).invoke(builder, 320)
        builderType.getMethod("setHeight", java.lang.Integer.TYPE).invoke(builder, 180)
        let format = builderType.getMethod("build").invoke(builder)
        let muxerType = java.lang.Class.forName("androidx.media3.muxer.Muxer")
        muxerType.getMethod("addTrack", java.lang.Class.forName("androidx.media3.common.Format")).invoke(muxer, format)
        muxerType.getMethod("close").invoke(muxer)
        #else
        throw unavailable()
        #endif
    }

    public static func copyFixture(name: String) throws -> String {
        #if SKIP
        let context = ProcessInfo.processInfo.androidContext
        // Tests run concurrently; never truncate a fixture another test is decoding.
        let file = File.createTempFile("swiftvideo-fixture-", "-" + name, context.getCacheDir())
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
        Array(try audioStats(path: path, duration: 2).prefix(3))
    }

    /// RGB samples at top-left pixel coordinate pairs, decoded independently of the renderer.
    public static func framePixels(path: String, timeUs: Int64, points: [Int]) throws -> [Double] {
        #if SKIP
        let retriever = MediaMetadataRetriever()
        defer { retriever.release() }
        retriever.setDataSource(path)
        guard let bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST) else {
            throw IllegalStateException("Cannot decode exported frame.")
        }
        defer { bitmap.recycle() }
        var result: [Double] = []
        for index in stride(from: 0, to: points.count, by: 2) {
            let pixel = bitmap.getPixel(points[index], points[index + 1])
            result.append(Double(Color.red(pixel))); result.append(Double(Color.green(pixel))); result.append(Double(Color.blue(pixel)))
        }
        return result
        #else
        throw unavailable()
        #endif
    }

    /// Foreground count, centroid, brightest RGB and ink width/height, for white titles over blue.
    public static func titleStats(path: String, timeUs: Int64) throws -> [Double] {
        #if SKIP
        let retriever = MediaMetadataRetriever()
        defer { retriever.release() }
        retriever.setDataSource(path)
        guard let bitmap = retriever.getFrameAtTime(timeUs, MediaMetadataRetriever.OPTION_CLOSEST) else {
            throw IllegalStateException("Cannot decode exported title frame.")
        }
        defer { bitmap.recycle() }
        var count = 0.0, xSum = 0.0, ySum = 0.0
        var red = 0, green = 0, blue = 0
        var minX = bitmap.getWidth(), maxX = -1, minY = bitmap.getHeight(), maxY = -1
        for y in 0..<bitmap.getHeight() {
            for x in 0..<bitmap.getWidth() {
                let pixel = bitmap.getPixel(x, y), r = Color.red(pixel), g = Color.green(pixel)
                if r > 70 && g > 70 {
                    count += 1; xSum += Double(x); ySum += Double(y)
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
                if r > red { red = r; green = g; blue = Color.blue(pixel) }
            }
        }
        return [count, count > 0 ? xSum / count : -1.0, count > 0 ? ySum / count : -1.0, Double(red), Double(green), Double(blue),
                Double(max(0, maxX - minX + 1)), Double(max(0, maxY - minY + 1))]
        #else
        throw unavailable()
        #endif
    }

    /// RMS at the beginning, middle and end, followed by central tone frequency and RMS.
    public static func audioStats(path: String, duration: Double) throws -> [Double] {
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
        var previous = 0.0
        var crossings = 0
        var toneCount = 0
        var toneSquares = 0.0
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
                        let slot = time < 0.05 ? 0 : ((time >= duration / 4 && time < duration / 4 + 0.05) ? 1 : ((time >= duration - 0.0625 && time < duration - 0.0125) ? 2 : -1))
                        if slot >= 0 { squares[slot] += sample * sample; counts[slot] += 1 }
                        if time >= duration / 4 && time < duration * 3 / 4 {
                            if toneCount > 0 && previous <= 0 && sample > 0 { crossings += 1 }
                            previous = sample; toneCount += 1; toneSquares += sample * sample
                        }
                    }
                }
                outputEnded = (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0
                decoder.releaseOutputBuffer(index, false)
            }
        }
        let levels = (0..<3).map { counts[$0] == 0 ? -1.0 : sqrt(squares[$0] / Double(counts[$0])) }
        return levels + [Double(crossings) * Double(sampleRate) / Double(max(1, toneCount)), sqrt(toneSquares / Double(max(1, toneCount)))]
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
