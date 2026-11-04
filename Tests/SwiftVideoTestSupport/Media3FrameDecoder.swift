// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.ImageFormat
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat

/// Independent SDR test readback. MediaMetadataRetriever can apply BT.601 to
/// BT.709 frames on emulators, even when ARGB_8888 is explicitly requested.
enum Media3FrameDecoder {
    static func decode(path: String, timeUs: Int64) throws -> Bitmap {
        let extractor = MediaExtractor()
        defer { extractor.release() }
        extractor.setDataSource(path)
        var selected: MediaFormat? = nil
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            if (format.getString(MediaFormat.KEY_MIME) ?? "").hasPrefix("video/") {
                selected = format
                extractor.selectTrack(index)
                break
            }
        }
        guard let format = selected, let mime = format.getString(MediaFormat.KEY_MIME) else {
            throw IllegalStateException("No video track for frame inspection")
        }
        extractor.seekTo(timeUs, MediaExtractor.SEEK_TO_PREVIOUS_SYNC)
        format.setInteger(MediaFormat.KEY_COLOR_FORMAT, MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible)
        let decoder = MediaCodec.createDecoderByType(mime)
        defer { decoder.release() }
        decoder.configure(format, nil, nil, 0)
        decoder.start()
        defer { decoder.stop() }
        let info = MediaCodec.BufferInfo()
        let deadline = java.lang.System.nanoTime() + Int64(10_000_000_000)
        var inputEnded = false
        var nearest: Frame? = nil
        var nearestTimeUs: Int64 = 0
        var nearestDistance = Int64.max
        while java.lang.System.nanoTime() < deadline {
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
            if index >= 0 {
                defer { decoder.releaseOutputBuffer(index, false) }
                if info.size > 0 {
                    let distance = abs(info.presentationTimeUs - timeUs)
                    if nearest == nil || distance < nearestDistance
                        || (distance == nearestDistance && info.presentationTimeUs > nearestTimeUs) {
                        guard let image = decoder.getOutputImage(index) else {
                            throw IllegalStateException("Decoder does not expose YUV planes")
                        }
                        defer { image.close() }
                        let frame = try Frame(image: image, outputFormat: decoder.getOutputFormat(index))
                        if distance == Int64(0) { return try bitmap(frame, format: format) }
                        nearest = frame
                        nearestTimeUs = info.presentationTimeUs
                        nearestDistance = distance
                    }
                }
                if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 {
                    if let frame = nearest { return try bitmap(frame, format: format) }
                    break
                }
            }
        }
        throw IllegalStateException("Cannot decode a frame at the requested time")
    }

    // Decoders can emit B-frames out of presentation order. Keep the closest
    // timestamp until an exact match or end of stream, preferring the later
    // frame on a tie. Copy only improving candidates so the codec can reuse
    // its buffers immediately, then convert the selected frame to RGB once.
    private final class Frame {
        let crop: android.graphics.Rect
        let planes: [Plane]
        let outputFormat: MediaFormat

        init(image: Image, outputFormat: MediaFormat) throws {
            guard image.getFormat() == ImageFormat.YUV_420_888 else {
                throw IllegalStateException("Frame inspection requires 8-bit YUV420")
            }
            self.crop = image.getCropRect()
            var planes: [Plane] = []
            for plane in image.getPlanes() { planes.append(Plane(plane)) }
            self.planes = planes
            self.outputFormat = outputFormat
        }
    }

    private final class Plane {
        let bytes: kotlin.ByteArray
        let rowStride: Int
        let pixelStride: Int

        init(_ plane: Image.Plane) {
            let buffer = plane.getBuffer().duplicate()
            self.bytes = kotlin.ByteArray(buffer.remaining())
            buffer.get(bytes)
            self.rowStride = plane.getRowStride()
            self.pixelStride = plane.getPixelStride()
        }
    }

    private static func bitmap(_ frame: Frame, format: MediaFormat) throws -> Bitmap {
        func metadata(_ key: String, fallback: Int) -> Int {
            // Android uses both absent keys and zero for unspecified metadata.
            for candidate in [format, frame.outputFormat] {
                if candidate.containsKey(key), candidate.getInteger(key) != 0 { return candidate.getInteger(key) }
            }
            return fallback
        }
        let standard = metadata(MediaFormat.KEY_COLOR_STANDARD, fallback: MediaFormat.COLOR_STANDARD_BT601_NTSC)
        let range = metadata(MediaFormat.KEY_COLOR_RANGE, fallback: MediaFormat.COLOR_RANGE_LIMITED)
        let transfer = metadata(MediaFormat.KEY_COLOR_TRANSFER, fallback: MediaFormat.COLOR_TRANSFER_SDR_VIDEO)
        guard transfer == MediaFormat.COLOR_TRANSFER_SDR_VIDEO,
              range == MediaFormat.COLOR_RANGE_LIMITED || range == MediaFormat.COLOR_RANGE_FULL else {
            throw IllegalStateException("Frame inspection requires SDR with a supported range")
        }
        let kr: Double
        let kb: Double
        switch standard {
        case MediaFormat.COLOR_STANDARD_BT709: kr = 0.2126; kb = 0.0722
        case MediaFormat.COLOR_STANDARD_BT601_PAL, MediaFormat.COLOR_STANDARD_BT601_NTSC: kr = 0.299; kb = 0.114
        default: throw IllegalStateException("Unsupported frame color standard: \(standard)")
        }
        let full = range == MediaFormat.COLOR_RANGE_FULL
        let crop = frame.crop
        let width = crop.width()
        let height = crop.height()
        let planes = frame.planes
        let pixels = kotlin.IntArray(width * height)
        func sample(_ plane: Plane, x: Int, y: Int) -> Double {
            let index = y * plane.rowStride + x * plane.pixelStride
            return Double(Int(plane.bytes[index]) & 255)
        }
        func channel(_ value: Double) -> Int { min(255, max(0, Int(value * 255 + 0.5))) }
        for y in 0..<height {
            for x in 0..<width {
                let sx = crop.left + x
                let sy = crop.top + y
                let luma = (sample(planes[0], x: sx, y: sy) - (full ? 0 : 16)) / (full ? 255 : 219)
                let cb = (sample(planes[1], x: sx / 2, y: sy / 2) - 128) / (full ? 255 : 224)
                let cr = (sample(planes[2], x: sx / 2, y: sy / 2) - 128) / (full ? 255 : 224)
                let red = luma + 2 * (1 - kr) * cr
                let blue = luma + 2 * (1 - kb) * cb
                let green = (luma - kr * red - kb * blue) / (1 - kr - kb)
                pixels[y * width + x] = Color.rgb(channel(red), channel(green), channel(blue))
            }
        }
        return Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
    }
}
#endif
