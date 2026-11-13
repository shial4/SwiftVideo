// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
import SwiftVideoMedia3
#if SKIP
import android.content.Context
import android.opengl.GLES20
import android.opengl.GLES30
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.framework.image.ByteBufferImageBuilder
import com.google.mediapipe.framework.image.MPImage
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.core.Delegate
import com.google.mediapipe.tasks.vision.core.RunningMode
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import java.io.File
import java.io.FileInputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.channels.FileChannel
#endif

/// The optional module owns model loading and inference. The core renderer only sees a GL effect.
public final class Media3PersonSegmentation {
    public static func makeEffect(modelPath: String, threshold: Double, softness: Double, useGPU: Bool) throws -> Media3VisualEffect {
        #if SKIP
        let file = File(modelPath)
        guard file.isFile(), file.canRead(), file.length() > 0, file.length() <= 16 * 1024 * 1024 else {
            throw IllegalArgumentException("The person segmentation model must be a readable local file of at most 16 MB.")
        }
        guard threshold.isFinite, softness.isFinite, threshold >= 0, softness >= 0, threshold + softness <= 1 else {
            throw IllegalArgumentException("Invalid person segmentation threshold or softness.")
        }
        return Media3VisualEffect(PersonSegmentationEffect(path: modelPath, threshold: threshold, softness: softness, useGPU: useGPU))
        #else
        throw NSError(domain: "SwiftVideoSegmentation", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "MediaPipe is available only on Android."])
        #endif
    }
}

#if SKIP
private final class PersonSegmentationEffect: GlEffect {
    private let path: String
    private let threshold: Double
    private let softness: Double
    private let useGPU: Bool
    init(path: String, threshold: Double, softness: Double, useGPU: Bool) {
        self.path = path; self.threshold = threshold; self.softness = softness; self.useGPU = useGPU
    }

    override func toGlShaderProgram(context: Context, useHdr: Bool) -> GlShaderProgram {
        guard !useHdr else { throw VideoFrameProcessingException("Person segmentation currently supports SDR only.") }
        do { return PersonSegmentationProgram(context: context, path: path, threshold: threshold, softness: softness, useGPU: useGPU) }
        catch { throw VideoFrameProcessingException(String(describing: error)) }
    }
}

/// Only 256x256 RGBA input and confidence floats cross the CPU/GPU boundary.
/// MediaPipe's public Java API requires these buffers even with GPU inference.
/// Downsampling, color conversion, mask interpolation and composition remain on the GPU.
private final class PersonSegmentationProgram: BaseGlShaderProgram {
    private var downsample: GlProgram?
    private var composite: GlProgram?
    private var segmenter: ImageSegmenter?
    private var modelBytes: ByteBuffer?
    private let pixels = ByteBuffer.allocateDirect(256 * 256 * 4).order(ByteOrder.nativeOrder())
    private let framebuffer = kotlin.IntArray(1)
    private var inputTexture = 0
    private var inputTarget = 0
    private var maskTexture = 0
    private var maskFormat = GLES20.GL_LUMINANCE
    private var width = 0
    private var height = 0
    private var lastTimestamp: Int64 = -1

    init(context: Context, path: String, threshold: Double, softness: Double, useGPU: Bool) {
        super.init(false, 1)
        do {
            let version = GLES20.glGetString(GLES20.GL_VERSION) ?? ""
            let extensions = GLES20.glGetString(GLES20.GL_EXTENSIONS) ?? ""
            let gl3 = version.contains("OpenGL ES 3")
            guard gl3 || extensions.contains("GL_OES_texture_float") else {
                throw VideoFrameProcessingException("Person segmentation requires float-texture support.")
            }
            maskFormat = gl3 ? GLES30.GL_RED : GLES20.GL_LUMINANCE
            let vertex = """
                attribute vec4 aPosition;
                varying vec2 vTexCoord;
                void main() {
                    gl_Position = aPosition;
                    vTexCoord = (aPosition.xy + 1.0) * 0.5;
                }
                """
            downsample = GlProgram(vertex, """
                precision highp float;
                uniform sampler2D uTexSampler;
                varying vec2 vTexCoord;
                void main() {
                    vec3 linear = clamp(texture2D(uTexSampler, vec2(vTexCoord.x, 1.0-vTexCoord.y)).rgb, 0.0, 1.0);
                    vec3 srgb = mix(linear * 12.92, 1.055 * pow(linear, vec3(1.0/2.4)) - 0.055,
                                    step(vec3(0.0031308), linear));
                    gl_FragColor = vec4(srgb, 1.0);
                }
                """)
            composite = GlProgram(vertex, """
                precision highp float;
                uniform sampler2D uTexSampler;
                uniform sampler2D uMask;
                uniform float uThreshold;
                uniform float uSoftness;
                varying vec2 vTexCoord;
                void main() {
                    vec2 p = vec2(vTexCoord.x, 1.0-vTexCoord.y) * 256.0 - 0.5;
                    vec2 base = (floor(p) + 0.5) / 256.0;
                    vec2 f = fract(p);
                    float a = texture2D(uMask, base).r;
                    float b = texture2D(uMask, base + vec2(1.0/256.0, 0.0)).r;
                    float c = texture2D(uMask, base + vec2(0.0, 1.0/256.0)).r;
                    float d = texture2D(uMask, base + vec2(1.0/256.0)).r;
                    float confidence = mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
                    float alpha = smoothstep(uThreshold, uThreshold + max(uSoftness, 0.000001), confidence);
                    vec4 color = texture2D(uTexSampler, vTexCoord);
                    gl_FragColor = vec4(color.rgb, color.a * alpha);
                }
                """)
            downsample!.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
            composite!.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
            composite!.setFloatUniform("uThreshold", Float(threshold))
            composite!.setFloatUniform("uSoftness", Float(softness))
            inputTexture = GlUtil.createTexture(256, 256, false)
            inputTarget = GlUtil.createFboForTexture(inputTexture)
            maskTexture = GlUtil.createTexture(256, 256, false)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTexture)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_NEAREST)
            GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_NEAREST)
            GLES20.glTexImage2D(GLES20.GL_TEXTURE_2D, 0, gl3 ? GLES30.GL_R32F : GLES20.GL_LUMINANCE,
                               256, 256, 0, maskFormat, GLES20.GL_FLOAT, nil)
            GlUtil.checkGlError()
            let stream = FileInputStream(path)
            defer { stream.close() }
            modelBytes = stream.getChannel().map(FileChannel.MapMode.READ_ONLY, 0, stream.getChannel().size())
            let options = ImageSegmenter.ImageSegmenterOptions.builder()
                .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(modelBytes!).setDelegate(useGPU ? Delegate.GPU : Delegate.CPU).build())
                .setRunningMode(RunningMode.VIDEO).setOutputCategoryMask(false).setOutputConfidenceMasks(true).build()
            segmenter = ImageSegmenter.createFromOptions(context, options)
        } catch {
            release()
            throw VideoFrameProcessingException(String(describing: error))
        }
    }

    override func configure(inputWidth: Int, inputHeight: Int) -> Size {
        width = inputWidth; height = inputHeight
        return Size(width, height)
    }

    override func drawFrame(inputTexId: Int, presentationTimeUs: Int64) {
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, framebuffer, 0)
        do {
            guard let downsample, let composite, let segmenter else {
                throw VideoFrameProcessingException("The person segmenter has finished.")
            }
            defer { GlUtil.focusFramebufferUsingCurrentContext(framebuffer[0], width, height) }
            GlUtil.focusFramebufferUsingCurrentContext(inputTarget, 256, 256)
            downsample.use()
            downsample.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            downsample.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            pixels.clear()
            GLES20.glReadPixels(0, 0, 256, 256, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
            GlUtil.checkGlError()
            let image = ByteBufferImageBuilder(pixels, 256, 256, MPImage.IMAGE_FORMAT_RGBA).build()
            defer { image.close() }
            // MediaPipe requires strictly increasing milliseconds; Media3 clocks use microseconds.
            let timestamp = max(lastTimestamp + 1, presentationTimeUs / 1000)
            let result = segmenter.segmentForVideo(image, timestamp)
            lastTimestamp = timestamp
            guard result.confidenceMasks().isPresent() else {
                throw VideoFrameProcessingException("MediaPipe returned no confidence masks.")
            }
            let masks = result.confidenceMasks().get()
            defer { for mask in masks { mask.close() } }
            guard masks.size == 1 || masks.size == 2 else {
                throw VideoFrameProcessingException("Use the documented binary Selfie Segmenter model.")
            }
            let mask = masks.get(masks.size - 1)
            guard mask.getWidth() == 256, mask.getHeight() == 256 else {
                throw VideoFrameProcessingException("Unexpected person confidence mask dimensions.")
            }
            let values = ByteBufferExtractor.extract(mask)
            guard values.remaining() == 256 * 256 * 4 else {
                throw VideoFrameProcessingException("Unexpected person confidence buffer size.")
            }
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, maskTexture)
            GLES20.glTexSubImage2D(GLES20.GL_TEXTURE_2D, 0, 0, 0, 256, 256, maskFormat, GLES20.GL_FLOAT, values)
            GlUtil.focusFramebufferUsingCurrentContext(framebuffer[0], width, height)
            composite.use()
            composite.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            composite.setSamplerTexIdUniform("uMask", maskTexture, 1)
            composite.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch { throw VideoFrameProcessingException(String(describing: error), presentationTimeUs) }
    }

    override func release() {
        do {
            defer { super.release() }
            defer { modelBytes = nil }
            defer { downsample?.delete(); downsample = nil }
            defer { composite?.delete(); composite = nil }
            defer { if maskTexture != 0 { GlUtil.deleteTexture(maskTexture); maskTexture = 0 } }
            defer { if inputTexture != 0 { GlUtil.deleteTexture(inputTexture); inputTexture = 0 } }
            defer { if inputTarget != 0 { GlUtil.deleteFbo(inputTarget); inputTarget = 0 } }
            segmenter?.close(); segmenter = nil
        } catch { throw VideoFrameProcessingException(String(describing: error)) }
    }
}
#endif
#endif
