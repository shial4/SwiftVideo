// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.util.GlUtil
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
#endif

/// Inspects the decoder-to-texture metadata without Media3's rendering pipeline.
public final class Media3SurfaceProbe {
    /// The first decoded texture's Android dataspace, or nil before API 33.
    public static func dataSpace(path: String) throws -> Int? {
        #if SKIP
        guard Build.VERSION.SDK_INT >= 33 else { return nil }
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
            throw IllegalStateException("No video track for surface inspection")
        }

        let display = GlUtil.getDefaultEglDisplay()
        defer { GlUtil.terminate(display) }
        let context = GlUtil.createEglContext(display)
        defer { GlUtil.destroyEglContext(display, context) }
        let placeholder = GlUtil.createFocusedPlaceholderEglSurface(context, display)
        defer { GlUtil.destroyEglSurface(display, placeholder) }
        let textureID = GlUtil.createExternalTexture()
        defer { GlUtil.deleteTexture(textureID) }
        let texture = SurfaceTexture(textureID)
        defer { texture.release() }
        texture.setDefaultBufferSize(format.getInteger(MediaFormat.KEY_WIDTH), format.getInteger(MediaFormat.KEY_HEIGHT))
        let available = CountDownLatch(1)
        texture.setOnFrameAvailableListener({ _ in available.countDown() }, Handler(Looper.getMainLooper()))
        let surface = Surface(texture)
        defer { surface.release() }
        let decoder = MediaCodec.createDecoderByType(mime)
        defer { decoder.release() }
        decoder.configure(format, surface, nil, 0)
        decoder.start()
        defer { decoder.stop() }

        let info = MediaCodec.BufferInfo()
        let deadline = java.lang.System.nanoTime() + Int64(10_000_000_000)
        var inputEnded = false
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
                let render = info.size > 0
                decoder.releaseOutputBuffer(index, render)
                if render {
                    guard available.await(Int64(5), TimeUnit.SECONDS) else {
                        throw IllegalStateException("Decoded frame did not reach its surface texture")
                    }
                    texture.updateTexImage()
                    return texture.getDataSpace()
                }
                if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 { break }
            }
        }
        throw IllegalStateException("No decoded frame for surface inspection")
        #else
        return nil
        #endif
    }
}
#endif
