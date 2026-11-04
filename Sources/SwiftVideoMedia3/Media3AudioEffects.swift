// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import androidx.media3.common.audio.SpeedProvider
import java.nio.ByteBuffer
import org.json.JSONArray

final class ConstantSpeedProvider: SpeedProvider {
    private let speed: Float
    init(speed: Float) { self.speed = speed }
    override func getSpeed(timeUs: Int64) -> Float { speed }
    override func getNextSpeedChangeTimeUs(timeUs: Int64) -> Int64 { C.TIME_UNSET }
}

/// Native JVM PCM processing: no per-sample Swift/JNI calls or buffer allocations.
/// Coefficients follow the W3C Audio EQ Cookbook; filters run in authored order.
final class EqualizerAudioProcessor: BaseAudioProcessor {
    private let filters: JSONArray
    private var bands: [Biquad] = []

    init(filters: JSONArray) { self.filters = filters; super.init() }

    static func validate(_ filters: JSONArray, sampleRate: Int) {
        for index in 0..<filters.length() {
            let frequency = filters.getJSONObject(index).getDouble("frequencyHz")
            guard frequency >= 20, frequency < Double(min(sampleRate, 48_000)) / 2 else {
                throw IllegalArgumentException("Audio filter frequency must be at least 20 Hz and below the source and processing Nyquist frequencies.")
            }
        }
    }

    override func onConfigure(inputAudioFormat: AudioProcessor.AudioFormat) -> AudioProcessor.AudioFormat {
        guard (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT),
              inputAudioFormat.channelCount >= 1, inputAudioFormat.channelCount <= 2 else {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        Self.validate(filters, sampleRate: inputAudioFormat.sampleRate)
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, inputAudioFormat.channelCount, C.ENCODING_PCM_FLOAT)
    }

    override func onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        bands = []
        for index in 0..<filters.length() {
            let filter = filters.getJSONObject(index)
            bands.append(Biquad(kind: filter.getString("kind"), frequency: filter.getDouble("frequencyHz"),
                                gain: filter.getDouble("gainDB"), bandwidth: filter.getDouble("bandwidthOctaves"),
                                sampleRate: Double(inputAudioFormat.sampleRate)))
        }
    }

    override func queueInput(inputBuffer: ByteBuffer) {
        let channels = inputAudioFormat.channelCount
        let floating = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        let count = inputBuffer.remaining() / (floating ? 4 : 2)
        let output = replaceOutputBuffer(count * 4)
        for index in 0..<count {
            var value = floating ? Double(inputBuffer.getFloat()) : Double(inputBuffer.getShort()) / 32768
            for band in bands { value = band.process(value, channel: index % channels) }
            output.putFloat(Float(value))
        }
        output.flip()
    }
}

private final class Biquad {
    private let b0: Double
    private let b1: Double
    private let b2: Double
    private let a1: Double
    private let a2: Double
    private let z1 = kotlin.DoubleArray(2)
    private let z2 = kotlin.DoubleArray(2)

    init(kind: String, frequency: Double, gain: Double, bandwidth: Double, sampleRate: Double) {
        let omega = 2 * Double.pi * frequency / sampleRate
        let sine = sin(omega)
        let cosine = cos(omega)
        let alpha: Double
        let a0: Double
        if kind == "parametricEQ" {
            let amplitude = pow(10.0, gain / 40)
            alpha = sine * kotlin.math.sinh(log(2.0) / 2 * bandwidth * omega / sine)
            // Near Nyquist, sinh can overflow for a wide band. Normalize by alpha
            // so its finite limiting response is retained instead of producing NaN.
            let inverse = alpha.isFinite ? 1 / alpha : 0.0
            a0 = inverse + 1 / amplitude
            b0 = (inverse + amplitude) / a0
            b1 = -2 * cosine * inverse / a0
            b2 = (inverse - amplitude) / a0
            a1 = b1; a2 = (inverse - 1 / amplitude) / a0
        } else {
            alpha = sine / sqrt(2.0)
            a0 = 1 + alpha
            if kind == "lowPass" {
                b0 = (1 - cosine) / (2 * a0); b1 = (1 - cosine) / a0
            } else if kind == "highPass" {
                b0 = (1 + cosine) / (2 * a0); b1 = -(1 + cosine) / a0
            } else { throw IllegalArgumentException("Unknown audio filter: " + kind) }
            b2 = b0; a1 = -2 * cosine / a0; a2 = (1 - alpha) / a0
        }
    }

    func process(_ input: Double, channel: Int) -> Double {
        let output = b0 * input + z1[channel]
        z1[channel] = b1 * input - a1 * output + z2[channel]
        z2[channel] = b2 * input - a2 * output
        return output
    }
}
#endif
