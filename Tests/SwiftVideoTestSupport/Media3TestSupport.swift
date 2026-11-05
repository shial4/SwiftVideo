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
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import java.io.File
import java.io.FileOutputStream
#endif

/// Integration fixtures and independent Android output inspection, linked only by tests.
public final class Media3TestSupport {
    /// Width, height, transparent/opaque pixels, top/bottom ink, and center RGBA.
    public static func layerImageStats(path: String) throws -> [Int] {
        #if SKIP
        guard let image = BitmapFactory.decodeFile(path) else { throw IllegalStateException("Cannot decode layer PNG") }
        defer { image.recycle() }
        var clear = 0, opaque = 0, top = 0, bottom = 0
        for y in 0..<image.getHeight() {
            for x in 0..<image.getWidth() {
                let color = image.getPixel(x, y)
                if Color.alpha(color) == 0 { clear += 1 }
                if Color.alpha(color) == 255 { opaque += 1 }
                if Color.alpha(color) > 127 {
                    if y < image.getHeight() / 2 { top += 1 } else { bottom += 1 }
                }
            }
        }
        let center = image.getPixel(image.getWidth() / 2, image.getHeight() / 2)
        return [image.getWidth(), image.getHeight(), clear, opaque, top, bottom,
                Color.red(center), Color.green(center), Color.blue(center), Color.alpha(center)]
        #else
        throw unavailable()
        #endif
    }

    public static func solidImage(red: Int, green: Int, blue: Int) throws -> String {
        #if SKIP
        let bitmap = Bitmap.createBitmap(320, 180, Bitmap.Config.ARGB_8888)
        defer { bitmap.recycle() }
        bitmap.eraseColor(Color.rgb(red, green, blue))
        let file = File.createTempFile("swiftvideo-solid-", ".png", ProcessInfo.processInfo.androidContext.getCacheDir())
        do {
            let output = FileOutputStream(file)
            defer { output.close() }
            guard bitmap.compress(Bitmap.CompressFormat.PNG, 100, output) else { throw IllegalStateException("Cannot save solid image") }
            return file.getAbsolutePath()
        } catch { file.delete(); throw error }
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

    /// Android extractor color standard, range, and transfer; absent values are -1.
    public static func videoColorInfo(path: String) throws -> [Int] {
        #if SKIP
        let extractor = MediaExtractor()
        defer { extractor.release() }
        extractor.setDataSource(path)
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME) ?? "").hasPrefix("video/") {
                return [MediaFormat.KEY_COLOR_STANDARD, MediaFormat.KEY_COLOR_RANGE, MediaFormat.KEY_COLOR_TRANSFER].map {
                    format.containsKey($0) ? format.getInteger($0) : -1
                }
            }
        }
        throw IllegalStateException("No video track for color inspection.")
        #else
        throw unavailable()
        #endif
    }

    public static func copyFrame(path: String, timeUs: Int64) throws -> String {
        #if SKIP
        let bitmap = try Media3FrameDecoder.decode(path: path, timeUs: timeUs)
        defer { bitmap.recycle() }
        let file = File.createTempFile("swiftvideo-frame-", ".png", ProcessInfo.processInfo.androidContext.getCacheDir())
        do {
            let output = FileOutputStream(file)
            defer { output.close() }
            guard bitmap.compress(Bitmap.CompressFormat.PNG, 100, output) else {
                throw IllegalStateException("Cannot save source frame.")
            }
            return file.getAbsolutePath()
        } catch {
            file.delete()
            throw error
        }
        #else
        throw unavailable()
        #endif
    }

    public static func frameStats(path: String, timeUs: Int64) throws -> [Double] {
        #if SKIP
        let retriever = MediaMetadataRetriever()
        defer { retriever.release() }
        retriever.setDataSource(path)
        let bitmap = try Media3FrameDecoder.decode(path: path, timeUs: timeUs)
        defer { bitmap.recycle() }
        let width = bitmap.getWidth()
        let height = bitmap.getHeight()
        let center = bitmap.getPixel(width / 2, Int(Double(height) * 0.5556))
        let left = bitmap.getPixel(width / 4, height / 2)
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
                Double(Color.red(overlay)), Double(Color.green(overlay)), Double(Color.blue(overlay)), count == 0 ? -1.0 : sum / Double(count),
                Double(Color.red(left)), Double(Color.green(left)), Double(Color.blue(left))]
        #else
        throw unavailable()
        #endif
    }

    public static func audioRMS(path: String) throws -> [Double] {
        Array(try audioStats(path: path, duration: 2).prefix(3))
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
