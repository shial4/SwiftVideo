// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import android.content.Context
import android.opengl.GLES20
import androidx.media3.common.VideoFrameProcessingException
import androidx.media3.common.util.GlProgram
import androidx.media3.common.util.GlUtil
import androidx.media3.common.util.Size
import androidx.media3.effect.BaseGlShaderProgram
import androidx.media3.effect.GlEffect
import androidx.media3.effect.GlShaderProgram
import org.json.JSONObject

/// Only app-registered shader source reaches this internal service boundary.
final class CustomShaderEffect: GlEffect {
    private let shader: JSONObject
    private let clock: JSONObject
    init(shader: JSONObject, clock: JSONObject) { self.shader = shader; self.clock = clock }

    override func toGlShaderProgram(context: Context, useHdr: Bool) -> GlShaderProgram {
        guard !useHdr else { throw VideoFrameProcessingException("Custom shaders currently support SDR only.") }
        do { return CustomShaderProgram(shader: shader, clock: clock) }
        catch { throw VideoFrameProcessingException(String(describing: error)) }
    }
}

/// Media3 constructs, draws and releases this object on the GL context's thread.
private final class CustomShaderProgram: BaseGlShaderProgram {
    private let program: GlProgram
    private let hasInputSampler: Bool
    private let effectOffset: Double
    private let effectDuration: Double
    private let sourceOffset: Double
    private let sourceRate: Double
    private let timeUniforms: [String]

    init(shader: JSONObject, clock: JSONObject) {
        super.init(false, 1)
        effectOffset = clock.getDouble("effectOffset")
        effectDuration = clock.getDouble("effectDuration")
        sourceOffset = clock.getDouble("sourceOffset")
        sourceRate = clock.getDouble("sourceRate")
        program = GlProgram("""
            attribute vec4 aPosition;
            varying vec2 vTexCoord;
            void main() {
                gl_Position = aPosition;
                vTexCoord = (aPosition.xy + 1.0) * 0.5;
            }
            """, shader.getString("fragmentShader"))
        hasInputSampler = program.getUniformLocation("uTexSampler") >= 0
        timeUniforms = ["uProjectTime", "uEffectTime", "uSourceTime", "uProgress"].filter { program.getUniformLocation($0) >= 0 }
        do {
            program.setBufferAttribute("aPosition", GlUtil.getNormalizedCoordinateBounds(), 4)
            if program.getUniformLocation("uEffectDuration") >= 0 {
                program.setFloatUniform("uEffectDuration", Float(effectDuration))
            }
            let uniforms = shader.getJSONObject("uniforms")
            let names = uniforms.keys()
            while names.hasNext() {
                let name = names.next()
                guard program.getUniformLocation(name) >= 0 else {
                    throw VideoFrameProcessingException("Custom shader has no active uniform: " + name)
                }
                let values = uniforms.getJSONArray(name)
                let floats = kotlin.FloatArray(values.length())
                for index in 0..<values.length() { floats[index] = Float(values.getDouble(index)) }
                program.setFloatsUniform(name, floats)
            }
        } catch {
            program.delete()
            throw VideoFrameProcessingException(String(describing: error))
        }
    }

    override func configure(inputWidth: Int, inputHeight: Int) -> Size {
        let texelSize = kotlin.FloatArray(2)
        texelSize[0] = Float(1) / Float(inputWidth)
        texelSize[1] = Float(1) / Float(inputHeight)
        program.setFloatsUniformIfPresent("uTexelSize", texelSize)
        return Size(inputWidth, inputHeight)
    }

    override func drawFrame(inputTexId: Int, presentationTimeUs: Int64) {
        do {
            program.use()
            // Constant-color generators may legitimately omit the input sampler.
            if hasInputSampler {
                program.setSamplerTexIdUniform("uTexSampler", inputTexId, 0)
            }
            let projectTime = Double(presentationTimeUs) / 1_000_000
            for name in timeUniforms {
                let value: Double
                switch name {
                case "uEffectTime": value = projectTime + effectOffset
                case "uSourceTime": value = projectTime * sourceRate + sourceOffset
                case "uProgress": value = max(0.0, min(1.0, (projectTime + effectOffset) / effectDuration))
                default: value = projectTime
                }
                program.setFloatUniform(name, Float(value))
            }
            program.bindAttributesAndUniforms()
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GlUtil.checkGlError()
        } catch { throw VideoFrameProcessingException(String(describing: error), presentationTimeUs) }
    }

    override func release() {
        // Release both allocations even if one of the GL cleanup calls fails.
        do { program.delete() }
        catch { super.release(); throw VideoFrameProcessingException(String(describing: error)) }
        super.release()
    }
}
#endif
