// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.effect.RgbMatrix
import java.nio.ByteBuffer
import org.json.JSONObject

final class ColorMatrixEffect: RgbMatrix {
    private let matrix: kotlin.FloatArray

    init(kind: String, value: Double) {
        matrix = kotlin.FloatArray(16)
        matrix[0] = Float(1); matrix[5] = Float(1); matrix[10] = Float(1); matrix[15] = Float(1)
        switch kind {
        case "brightness":
            matrix[12] = Float(value); matrix[13] = Float(value); matrix[14] = Float(value)
        case "contrast":
            matrix[0] = Float(value); matrix[5] = Float(value); matrix[10] = Float(value)
            matrix[12] = Float((1 - value) / 2); matrix[13] = Float((1 - value) / 2); matrix[14] = Float((1 - value) / 2)
        case "saturation":
            let luminance = [0.2126, 0.7152, 0.0722]
            for row in 0..<3 {
                for column in 0..<3 { matrix[column * 4 + row] = Float((1 - value) * luminance[column] + (row == column ? value : 0.0)) }
            }
        case "sepia":
            let sepia = [0.393, 0.769, 0.189, 0.349, 0.686, 0.168, 0.272, 0.534, 0.131]
            for row in 0..<3 {
                for column in 0..<3 { matrix[column * 4 + row] = Float(value * sepia[row * 3 + column] + (row == column ? 1 - value : 0.0)) }
            }
        default: throw IllegalArgumentException("Unknown color effect: " + kind)
        }
    }

    override func getMatrix(presentationTimeUs: Int64, useHdr: Bool) -> kotlin.FloatArray { matrix }
}

/// Applies the piecewise-linear gain envelope resolved by the shared Swift model.
/// Media3 performs resampling and mixing after this per-item PCM processor.
final class EnvelopeAudioProcessor: BaseAudioProcessor {
    private var frames: Int64 = 0
    private let times: [Double]
    private let gains: [Double]
    private let left: Double
    private let right: Double

    init(clip: JSONObject) {
        let points = clip.getJSONArray("envelope")
        var times: [Double] = []
        var gains: [Double] = []
        for index in 0..<points.length() {
            times.append(points.getJSONObject(index).getDouble("seconds"))
            gains.append(points.getJSONObject(index).getDouble("gain"))
        }
        self.times = times; self.gains = gains
        left = clip.getDouble("leftGain"); right = clip.getDouble("rightGain")
        super.init()
    }

    override func onConfigure(inputAudioFormat: AudioProcessor.AudioFormat) -> AudioProcessor.AudioFormat {
        guard (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT),
              inputAudioFormat.channelCount >= 1, inputAudioFormat.channelCount <= 2 else {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, 2, C.ENCODING_PCM_16BIT)
    }

    override func onFlush(streamMetadata: AudioProcessor.StreamMetadata) { frames = 0 }

    override func queueInput(inputBuffer: ByteBuffer) {
        let channels = inputAudioFormat.channelCount
        let floating = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        let bytesPerSample = floating ? 4 : 2
        let count = inputBuffer.remaining() / (channels * bytesPerSample)
        let output = replaceOutputBuffer(count * 4)
        for _ in 0..<count {
            let first = floating ? Double(inputBuffer.getFloat()) : Double(inputBuffer.getShort()) / 32768
            let second = channels == 1 ? first : (floating ? Double(inputBuffer.getFloat()) : Double(inputBuffer.getShort()) / 32768)
            let amplitude = gain(at: Double(frames) / Double(inputAudioFormat.sampleRate))
            output.putShort(pcm(first * amplitude * left))
            output.putShort(pcm(second * amplitude * right))
            frames += 1
        }
        output.flip()
    }

    private func pcm(_ value: Double) -> Int16 {
        if !value.isFinite { return 0 }
        return Int16(max(-32768, min(32767, Int(value * 32768))))
    }

    private func gain(at time: Double) -> Double {
        if times.isEmpty { return 0 }
        if time <= times[0] { return gains[0] }
        for index in 1..<times.count where time < times[index] {
            let progress = (time - times[index - 1]) / (times[index] - times[index - 1])
            return gains[index - 1] + (gains[index] - gains[index - 1]) * progress
        }
        return gains[gains.count - 1]
    }
}
#endif
