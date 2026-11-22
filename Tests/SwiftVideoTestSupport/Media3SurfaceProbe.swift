// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.opengl.GLES20
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.Surface
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.GlProgram
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
#endif

/// Inspects the decoder-to-texture metadata without Media3's rendering pipeline.
public final class Media3SurfaceProbe {
    /// Dataspace (-1 before API 33), then RGB at the left and right quarter points.
    public static func firstFrame(path: String) throws -> [Int] {
        #if SKIP
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
                    let dataSpace = Build.VERSION.SDK_INT >= 33 ? texture.getDataSpace() : -1
                    // Sample Android's external texture directly. No Media3 frame
                    // processor, effect, transfer function, or encoder is involved.
                    let output = GlUtil.createTexture(2, 1, false)
                    defer { GlUtil.deleteTexture(output) }
                    let framebuffer = GlUtil.createFboForTexture(output)
                    defer { GlUtil.deleteFbo(framebuffer) }
                    GlUtil.focusFramebuffer(display, context, placeholder, framebuffer, 2, 1)
                    let program = GlProgram("""
                    attribute vec4 aPosition;
                    attribute vec4 aTexCoord;
                    uniform mat4 uTexTransform;
                    varying vec2 vTexCoord;
                    void main() {
                        gl_Position = aPosition;
                        vTexCoord = (uTexTransform * aTexCoord).xy;
                    }
                    """, """
                    #extension GL_OES_EGL_image_external : require
                    precision mediump float;
                    uniform samplerExternalOES uTexture;
                    varying vec2 vTexCoord;
                    void main() { gl_FragColor = texture2D(uTexture, vTexCoord); }
                    """)
                    defer { program.delete() }
                    let transform = GlUtil.create4x4IdentityMatrix()
                    texture.getTransformMatrix(transform)
                    program.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
                    program.setBufferAttribute("aTexCoord", GlUtil.getTextureCoordinateBounds(), 4)
                    program.setFloatsUniform("uTexTransform", transform)
                    program.setSamplerTexIdUniform("uTexture", textureID, 0)
                    program.setExternalTexturesRequireNearestSampling(true)
                    program.bindAttributesAndUniforms()
                    GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
                    GlUtil.checkGlError()
                    let pixels = ByteBuffer.allocateDirect(8)
                    GLES20.glReadPixels(0, 0, 2, 1, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
                    GlUtil.checkGlError()
                    return [dataSpace] + [0, 1, 2, 4, 5, 6].map { Int(pixels.get($0)) & 255 }
                }
                if (info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0 { break }
            }
        }
        throw IllegalStateException("No decoded frame for surface inspection")
        #else
        return []
        #endif
    }
}
#endif
