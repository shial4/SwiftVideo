// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import java.nio.ByteBuffer
import java.nio.ByteOrder

final class MotionTitleEffect: GlEffect {
    private let raster: MotionTitleRaster
    private let sample: (String, Double) throws -> Data
    init(raster: MotionTitleRaster, sample: @escaping (String, Double) throws -> Data) {
        self.raster = raster; self.sample = sample
    }

    override func toGlShaderProgram(context: Context, useHdr: Bool) -> GlShaderProgram {
        guard !useHdr else { throw VideoFrameProcessingException("Motion titles currently support SDR only.") }
        do { return MotionTitleProgram(raster: raster, sample: sample) }
        catch { throw VideoFrameProcessingException(String(describing: error)) }
    }
}

/// Glyphs are rasterized once. Each frame transfers only five floats per unit;
/// transforms, blending and conversion back to straight alpha remain on the GPU.
private final class MotionTitleProgram: BaseGlShaderProgram {
    private let raster: MotionTitleRaster
    private let sample: (String, Double) throws -> Data
    private let units: GlProgram
    private let output: GlProgram
    private let bounds = kotlin.FloatArray(4)
    private let atlas = kotlin.FloatArray(4)
    private let transform = kotlin.FloatArray(4)
    private let framebuffer = kotlin.IntArray(1)
    private var texture = 0
    private var target = 0

    init(raster: MotionTitleRaster, sample: @escaping (String, Double) throws -> Data) {
        self.raster = raster; self.sample = sample
        super.init(false, 1)
        units = GlProgram("""
            attribute vec4 aPosition;
            uniform vec2 uSize;
            uniform vec4 uBounds;
            uniform vec4 uAtlas;
            uniform vec4 uTransform;
            varying vec2 vTexCoord;
            void main() {
                vec2 p = aPosition.xy * uBounds.zw * 0.5 * uTransform.z;
                float angle = -radians(uTransform.w);
                p = mat2(cos(angle), sin(angle), -sin(angle), cos(angle)) * p;
                p += uBounds.xy + vec2(uTransform.x, -uTransform.y) * uSize;
                gl_Position = vec4(p * 2.0 / uSize - 1.0, 0.0, 1.0);
                vTexCoord = uAtlas.xy + (aPosition.xy + 1.0) * 0.5 * uAtlas.zw;
            }
            """, """
            precision mediump float;
            uniform sampler2D uTexSampler;
            uniform float uOpacity;
            varying vec2 vTexCoord;
            void main() {
                vec4 color = texture2D(uTexSampler, vTexCoord);
                float alpha = color.a * uOpacity;
                gl_FragColor = vec4(color.rgb * alpha, alpha);
            }
            """)
        do {
            output = GlProgram("""
                attribute vec4 aPosition;
                varying vec2 vTexCoord;
                void main() {
                    gl_Position = aPosition;
                    vTexCoord = (aPosition.xy + 1.0) * 0.5;
                }
                """, """
                precision mediump float;
                uniform sampler2D uTexSampler;
                varying vec2 vTexCoord;
                void main() {
                    vec4 color = texture2D(uTexSampler, vTexCoord);
                    gl_FragColor = color.a > 0.0 ? vec4(color.rgb / color.a, color.a) : vec4(0.0);
                }
                """)
        } catch {
            units.delete()
            throw VideoFrameProcessingException(String(describing: error))
        }
        do {
            let size = kotlin.FloatArray(2)
            size[0] = Float(raster.width); size[1] = Float(raster.height)
            units.setFloatsUniform("uSize", size)
            units.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
            output.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
        } catch {
            defer { output.delete() }
            units.delete()
            throw VideoFrameProcessingException(String(describing: error))
        }
    }

    override func configure(inputWidth: Int, inputHeight: Int) -> Size {
        // Media3 may scale decoded image textures. UVs remain normalized to the
        // original atlas, and this stage restores the title's logical canvas.
        do {
            if texture == 0 {
                texture = GlUtil.createTexture(raster.width, raster.height, false)
                target = GlUtil.createFboForTexture(texture)
            }
            return Size(raster.width, raster.height)
        } catch { throw VideoFrameProcessingException(String(describing: error)) }
    }

    override func drawFrame(inputTexId: Int, presentationTimeUs: Int64) {
        GLES20.glGetIntegerv(GLES20.GL_FRAMEBUFFER_BINDING, framebuffer, 0)
        do {
            let data = try sample(raster.id, Double(presentationTimeUs))
            guard data.count == raster.unitCount * 5 * 4 else {
                throw IllegalArgumentException("Invalid motion title transform buffer.")
            }
            let values = ByteBuffer.wrap(data.kotlin(nocopy: true)).order(ByteOrder.LITTLE_ENDIAN)
            GlUtil.focusFramebufferUsingCurrentContext(target, raster.width, raster.height)
            GlUtil.clearFocusedBuffers()
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFuncSeparate(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA, GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            units.use()
            units.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            for piece in raster.pieces {
                let offset = piece.index * 20
                let opacity = values.getFloat(offset + 16)
                if opacity <= 0 { continue }
                for index in 0..<4 { transform[index] = values.getFloat(offset + index * 4) }
                bounds[0] = Float(piece.bounds.exactCenterX())
                bounds[1] = Float(raster.height) - piece.bounds.exactCenterY()
                bounds[2] = Float(piece.bounds.width()); bounds[3] = Float(piece.bounds.height())
                atlas[0] = Float(piece.atlas.left) / Float(raster.atlasWidth)
                atlas[1] = 1 - Float(piece.atlas.bottom) / Float(raster.atlasHeight)
                atlas[2] = Float(piece.atlas.width()) / Float(raster.atlasWidth)
                atlas[3] = Float(piece.atlas.height()) / Float(raster.atlasHeight)
                units.setFloatsUniform("uBounds", bounds)
                units.setFloatsUniform("uAtlas", atlas)
                units.setFloatsUniform("uTransform", transform)
                units.setFloatUniform("uOpacity", opacity)
                units.bindAttributesAndUniforms()
                GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            }
            GLES20.glDisable(GLES20.GL_BLEND)
            GlUtil.focusFramebufferUsingCurrentContext(framebuffer[0], raster.width, raster.height)
            output.use()
            output.setSamplerTexIdUniform("uTexSampler", texture, 0)
            output.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch {
            GLES20.glDisable(GLES20.GL_BLEND)
            GlUtil.focusFramebufferUsingCurrentContext(framebuffer[0], raster.width, raster.height)
            throw VideoFrameProcessingException(String(describing: error), presentationTimeUs)
        }
    }

    override func release() {
        // Nested defers release every allocation even if an earlier call fails.
        do {
            defer { super.release() }
            defer { output.delete() }
            defer { units.delete() }
            defer { if texture != 0 { GlUtil.deleteTexture(texture); texture = 0 } }
            if target != 0 { GlUtil.deleteFbo(target); target = 0 }
        } catch { throw VideoFrameProcessingException(String(describing: error)) }
    }
}
#endif
