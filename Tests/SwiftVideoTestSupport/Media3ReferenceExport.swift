// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.os.Handler
import android.os.Looper
import android.media.metrics.LogSessionId
import android.view.Surface
import androidx.media3.common.__
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.Clock
import androidx.media3.common.util.GlRect
import androidx.media3.common.util.Size
import androidx.media3.effect.ByteBufferGlEffect
import androidx.media3.transformer.__
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicIntegerArray
import java.util.concurrent.atomic.AtomicReference
#endif

/// Independent Media3 control, without SwiftVideo composition or render planning.
public final class Media3ReferenceExport {
    #if SKIP
    private let handler = Handler(Looper.getMainLooper())
    private let state = AtomicInteger(0)
    private let failure = AtomicReference<String>("")
    private let samples = AtomicIntegerArray(8)
    private let decoderColors = AtomicIntegerArray(3)
    private var transformer: Transformer?
    #endif

    public init() {}

    public func start(source: String, destination: String, imageDurationMilliseconds: Int64 = 0) throws {
        #if SKIP
        guard state.compareAndSet(0, 1) else { throw IllegalStateException("Reference export already started") }
        handler.post {
            do {
                // Readback requires decoding and encoding; the probe leaves every frame unchanged.
                let effects = java.util.ArrayList<Effect>()
                effects.add(ByteBufferGlEffect<Int>(ReferencePixelProbe(samples: self.samples)))
                let context = ProcessInfo.processInfo.androidContext
                let decoder = ReferenceDecoderFactory(delegate: DefaultDecoderFactory.Builder(context).build(), colors: self.decoderColors)
                let encoder = DefaultEncoderFactory.Builder(context)
                    .setEnableFallback(false)
                    .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(4_000_000).build())
                    .build()
                let exporterBuilder = Transformer.Builder(context)
                    .setVideoMimeType(MimeTypes.VIDEO_H264)
                    .setEncoderFactory(encoder)
                    .addListener(ReferenceExportListener(completed: { self.state.set(2) }, failed: { message in
                        self.failure.set(message)
                        self.state.set(-1)
                    }))
                if imageDurationMilliseconds == Int64(0) {
                    exporterBuilder.setAssetLoaderFactory(ExoPlayerAssetLoader.Factory(context, decoder, Clock.DEFAULT))
                }
                let exporter = exporterBuilder.build()
                self.transformer = exporter
                let media = MediaItem.Builder().setUri(source)
                if imageDurationMilliseconds > 0 { media.setImageDurationMs(imageDurationMilliseconds).setMimeType(MimeTypes.IMAGE_PNG) }
                let item = EditedMediaItem.Builder(media.build()).setRemoveAudio(true)
                    .setEffects(Effects(java.util.ArrayList<AudioProcessor>(), effects))
                if imageDurationMilliseconds > 0 { item.setFrameRate(30).setDurationUs(imageDurationMilliseconds * 1000) }
                exporter.start(item.build(), destination)
            } catch {
                self.failure.set(String(describing: error))
                self.state.set(-1)
            }
        }
        #endif
    }

    public func status() -> Int {
        #if SKIP
        return state.get()
        #else
        return -1
        #endif
    }

    public func failureMessage() -> String {
        #if SKIP
        return failure.get()
        #else
        return "Android reference exporter is unavailable"
        #endif
    }

    /// Two pre-encoder samples, each containing timestamp (us), red, green, and blue.
    /// Components use Media3's effect working space, not display-encoded sRGB.
    public func frameSamples() -> [Double] {
        #if SKIP
        return (0..<8).map { Double(samples.get($0)) }
        #else
        return []
        #endif
    }

    /// Color standard, range, and transfer passed unchanged to Media3's decoder.
    public func decoderColorInfo() -> [Int] {
        #if SKIP
        return (0..<3).map { decoderColors.get($0) }
        #else
        return []
        #endif
    }

    public func cancel() {
        #if SKIP
        handler.post { self.transformer?.cancel(); self.transformer = nil }
        #endif
    }
}

#if SKIP
private final class ReferenceDecoderFactory: Codec.DecoderFactory {
    private let delegate: DefaultDecoderFactory
    private let colors: AtomicIntegerArray

    init(delegate: DefaultDecoderFactory, colors: AtomicIntegerArray) {
        self.delegate = delegate; self.colors = colors
    }

    override func createForAudioDecoding(format: Format, logSessionId: LogSessionId?) -> Codec {
        delegate.createForAudioDecoding(format, logSessionId)
    }

    override func createForVideoDecoding(format: Format, outputSurface: Surface,
                                        requestSdrToneMapping: Bool, logSessionId: LogSessionId?) -> Codec {
        colors.set(0, format.colorInfo?.colorSpace ?? -1)
        colors.set(1, format.colorInfo?.colorRange ?? -1)
        colors.set(2, format.colorInfo?.colorTransfer ?? -1)
        return delegate.createForVideoDecoding(format, outputSurface, requestSdrToneMapping, logSessionId)
    }
}

private final class ReferencePixelProbe: ByteBufferGlEffect.Processor<Int> {
    private let samples: AtomicIntegerArray
    private var width = 0
    private var height = 0

    init(samples: AtomicIntegerArray) { self.samples = samples }

    override func configure(inputWidth: Int, inputHeight: Int) -> Size {
        width = inputWidth; height = inputHeight
        return Size(inputWidth, inputHeight)
    }

    override func getScaledRegion(presentationTimeUs: Int64) -> GlRect { GlRect(width, height) }

    override func processImage(image: ByteBufferGlEffect.Image, presentationTimeUs: Int64) -> ListenableFuture<Int> {
        for sample in 0..<2 {
            let target = sample == 0 ? Int64(500_000) : Int64(3_500_000)
            if abs(presentationTimeUs - target) < 10_000 {
                let pixel = ((image.height / 2) * image.width + image.width / 4) * 4
                samples.set(sample * 4, Int(presentationTimeUs))
                for channel in 0..<3 {
                    samples.set(sample * 4 + channel + 1, Int(image.pixelBuffer.get(pixel + channel)) & 255)
                }
            }
        }
        return Futures.immediateFuture(0)
    }

    override func finishProcessingAndBlend(outputFrame: GlTextureInfo, presentationTimeUs: Int64, result: Int) {}
    override func release() {}
}

private final class ReferenceExportListener: Transformer.Listener {
    let completed: () -> Void
    let failed: (String) -> Void
    init(completed: @escaping () -> Void, failed: @escaping (String) -> Void) {
        self.completed = completed; self.failed = failed
    }
    override func onCompleted(composition: Composition, exportResult: ExportResult) { completed() }
    override func onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
        failed(exportException.toString() + "; cause=" + (exportException.cause?.toString() ?? "unknown"))
    }
}
#endif
#endif
