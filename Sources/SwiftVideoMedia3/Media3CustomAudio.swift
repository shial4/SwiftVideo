// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.audio.BaseAudioProcessor
import java.nio.ByteBuffer
import java.nio.ByteOrder

/// A block-level bridge to app-owned native Swift DSP, after Media3 speed processing.
/// Byte arrays cross JNI in bulk. No sample-level callbacks or boxed Float arrays.
final class CustomAudioProcessor: BaseAudioProcessor {
    private let id: String
    private let process: (String, Int, Int, Data, Bool) throws -> Data
    private var pcm = ByteBuffer.allocate(0).order(ByteOrder.LITTLE_ENDIAN)

    init(id: String, process: @escaping (String, Int, Int, Data, Bool) throws -> Data) {
        self.id = id; self.process = process; super.init()
    }

    override func onConfigure(inputAudioFormat: AudioProcessor.AudioFormat) -> AudioProcessor.AudioFormat {
        guard (inputAudioFormat.encoding == C.ENCODING_PCM_16BIT || inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT),
              inputAudioFormat.channelCount >= 1, inputAudioFormat.channelCount <= 2 else {
            throw AudioProcessor.UnhandledAudioFormatException(inputAudioFormat)
        }
        return AudioProcessor.AudioFormat(inputAudioFormat.sampleRate, inputAudioFormat.channelCount, C.ENCODING_PCM_FLOAT)
    }

    override func onFlush(streamMetadata: AudioProcessor.StreamMetadata) {
        _ = invoke(Data(), reset: true)
    }

    override func queueInput(inputBuffer: ByteBuffer) {
        let floating = inputAudioFormat.encoding == C.ENCODING_PCM_FLOAT
        let bytesPerSample = floating ? 4 : 2
        guard inputBuffer.remaining() % (bytesPerSample * inputAudioFormat.channelCount) == 0 else {
            throw IllegalArgumentException("Custom audio received incomplete PCM frames.")
        }
        let bytes = inputBuffer.remaining() / bytesPerSample * 4
        if bytes == 0 { return }
        if pcm.capacity() != bytes { pcm = ByteBuffer.allocate(bytes).order(ByteOrder.LITTLE_ENDIAN) }
        pcm.clear()
        while inputBuffer.hasRemaining() {
            pcm.putFloat(floating ? inputBuffer.getFloat() : Float(inputBuffer.getShort()) / 32768)
        }
        let result = invoke(Data(platformValue: pcm.array()), reset: false)
        let values = result.kotlin(nocopy: true)
        guard values.size == bytes else { throw IllegalArgumentException("A custom audio effect changed its buffer size.") }
        let output = replaceOutputBuffer(bytes)
        output.put(values)
        output.flip()
    }

    override func onReset() { pcm = ByteBuffer.allocate(0).order(ByteOrder.LITTLE_ENDIAN) }

    private func invoke(_ data: Data, reset: Bool) -> Data {
        do { return try process(id, inputAudioFormat.sampleRate, inputAudioFormat.channelCount, data, reset) }
        // Skip's bridged Swift Error is a checked Java Exception. Transformer catches
        // RuntimeException on its worker thread; translate here so failure releases the
        // export instead of escaping the looper and terminating the application.
        catch { throw IllegalStateException(String(describing: error)) }
    }
}
#endif
