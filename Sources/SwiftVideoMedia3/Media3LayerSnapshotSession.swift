// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.graphics.Matrix
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.opengl.GLES20
import androidx.media3.common.__
import androidx.media3.common.util.ConstantRateTimestampIterator
import androidx.media3.common.util.GlUtil
import androidx.media3.effect.DefaultVideoFrameProcessor
import androidx.media3.effect.GlTextureProducer
import java.io.FileOutputStream
import java.nio.ByteBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executor
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
#endif

/// Swift-authored boundary for transparent paused layers. No video encoder is opened.
public final class Media3LayerSnapshotSession {
    #if SKIP
    private let status: AtomicInteger = AtomicInteger(0)
    private let failure: AtomicReference<String> = AtomicReference<String>("")
    private let cancelled: AtomicBoolean = AtomicBoolean(false)
    #endif

    public init() {
        #if SKIP
        java.lang.System.loadLibrary("SkipBridge")
        #endif
    }

    public func start(json: String, sourceSeconds: Double, outputPath: String) throws {
        #if SKIP
        guard status.compareAndSet(0, 1) else { throw IllegalStateException("Layer renderer already started") }
        java.lang.Thread({
            do {
                try self.render(JSONObject(json), sourceSeconds: sourceSeconds, outputPath: outputPath)
                self.status.set(self.cancelled.get() ? 3 : 2)
            } catch {
                self.failure.set(String(describing: error))
                self.status.set(self.cancelled.get() ? 3 : -1)
            }
        }, "SwiftVideo layer image").start()
        #else
        throw NSError(domain: "SwiftVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Media3 requires Android."])
        #endif
    }

    public func currentStatus() -> Int {
        #if SKIP
        return status.get()
        #else
        return -1
        #endif
    }

    public func failureMessage() -> String {
        #if SKIP
        return failure.get()
        #else
        return "Media3 requires Android."
        #endif
    }

    public func cancel() {
        #if SKIP
        cancelled.set(true)
        #endif
    }

    #if SKIP
    private func render(_ plan: JSONObject, sourceSeconds: Double, outputPath: String) throws {
        let context = ProcessInfo.processInfo.androidContext
        let clip = plan.getJSONArray("clips").getJSONObject(0)
        let builder = Media3CompositionBuilder()
        let bitmap: Bitmap
        switch clip.getString("kind") {
        case "text":
            bitmap = try builder.textImage(clip, width: plan.getInt("width"), height: plan.getInt("height"))
        case "image":
            bitmap = ImageDecoder.decodeBitmap(ImageDecoder.createSource(context.getContentResolver(), Uri.parse(clip.getString("url"))), { decoder, _, _ in
                decoder.setAllocator(ImageDecoder.ALLOCATOR_SOFTWARE)
            })
        case "video":
            let retriever = MediaMetadataRetriever()
            defer { retriever.release() }
            retriever.setDataSource(context, Uri.parse(clip.getString("url")))
            guard sourceSeconds.isFinite, sourceSeconds >= 0, sourceSeconds < 9_000_000_000_000,
                  let duration = retriever.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION),
                  let milliseconds = Double(duration), sourceSeconds * 1000 < milliseconds else {
                throw IllegalArgumentException("The preview time is outside the video source.")
            }
            guard let image = retriever.getFrameAtTime(Int64(sourceSeconds * 1_000_000), MediaMetadataRetriever.OPTION_CLOSEST) else {
                throw IllegalStateException("Cannot decode a layer frame.")
            }
            bitmap = image
        default: throw IllegalArgumentException("A visual layer is required.")
        }
        defer { if !bitmap.isRecycled() { bitmap.recycle() } }
        let ready = CountDownLatch(1)
        let rendered = CountDownLatch(1)
        let output = AtomicReference<Bitmap?>(nil)
        let error = AtomicReference<String>("")
        let listener = LayerFrameListener(ready: ready, rendered: rendered, error: error)
        let textureListener = LayerTextureListener(output: output, rendered: rendered, error: error)
        let processor = DefaultVideoFrameProcessor.Factory.Builder()
            .setTextureOutput(textureListener, 1).build()
            .create(context, DebugViewProvider.NONE, ColorInfo.SRGB_BT709_FULL, true, LayerDirectExecutor(), listener)
        defer {
            processor.release()
            output.get()?.recycle()
        }
        let effects = builder.visualEffects(clip, width: plan.getInt("width"), height: plan.getInt("height"))
        let format = Format.Builder().setWidth(bitmap.getWidth()).setHeight(bitmap.getHeight())
            .setColorInfo(ColorInfo.SRGB_BT709_FULL).build()
        processor.registerInputStream(VideoFrameProcessor.INPUT_TYPE_BITMAP, format, effects, Int64(0))
        try wait(ready, error: error)
        guard processor.queueInputBitmap(bitmap, ConstantRateTimestampIterator(Int64(1), Float(1))) else {
            throw IllegalStateException("Layer processor did not accept its image.")
        }
        processor.signalEndOfInput()
        try wait(rendered, error: error)
        guard let image = output.get() else { throw IllegalStateException("The layer renderer produced no image.") }
        let stream = FileOutputStream(outputPath)
        defer { stream.close() }
        guard image.compress(Bitmap.CompressFormat.PNG, 100, stream) else {
            throw IllegalStateException("Cannot encode the layer image.")
        }
    }

    private func wait(_ latch: CountDownLatch, error: AtomicReference<String>) throws {
        let deadline = java.lang.System.nanoTime() + Int64(15_000_000_000)
        while !latch.await(Int64(20), TimeUnit.MILLISECONDS) {
            guard !cancelled.get() else { throw IllegalStateException("Layer rendering cancelled") }
            guard error.get().isEmpty else { throw IllegalStateException(error.get()) }
            guard java.lang.System.nanoTime() < deadline else { throw IllegalStateException("Layer rendering timed out") }
        }
        guard !cancelled.get() else { throw IllegalStateException("Layer rendering cancelled") }
        guard error.get().isEmpty else { throw IllegalStateException(error.get()) }
    }
    #endif
}

#if SKIP
private final class LayerDirectExecutor: Executor {
    override func execute(_ command: java.lang.Runnable) { command.run() }
}

private final class LayerFrameListener: VideoFrameProcessor.Listener {
    let ready: CountDownLatch
    let rendered: CountDownLatch
    let error: AtomicReference<String>
    init(ready: CountDownLatch, rendered: CountDownLatch, error: AtomicReference<String>) {
        self.ready = ready; self.rendered = rendered; self.error = error
    }
    override func onInputStreamRegistered(_ inputType: Int, _ format: Format, _ effects: kotlin.collections.List<Effect>) {
        ready.countDown()
    }
    override func onError(_ exception: VideoFrameProcessingException) {
        error.set(exception.toString()); ready.countDown(); rendered.countDown()
    }
}

private final class LayerTextureListener: GlTextureProducer.Listener {
    let output: AtomicReference<Bitmap?>
    let rendered: CountDownLatch
    let error: AtomicReference<String>
    init(output: AtomicReference<Bitmap?>, rendered: CountDownLatch, error: AtomicReference<String>) {
        self.output = output; self.rendered = rendered; self.error = error
    }
    override func onTextureRendered(_ producer: GlTextureProducer, _ texture: GlTextureInfo,
                                     _ presentationTimeUs: Int64, _ syncObject: Int64) {
        defer { producer.releaseOutputTexture(presentationTimeUs); rendered.countDown() }
        do {
            GlUtil.focusFramebufferUsingCurrentContext(texture.fboId, texture.width, texture.height)
            let pixels = ByteBuffer.allocateDirect(texture.width * texture.height * 4)
            GLES20.glReadPixels(0, 0, texture.width, texture.height, GLES20.GL_RGBA, GLES20.GL_UNSIGNED_BYTE, pixels)
            GlUtil.checkGlError()
            let raw = Bitmap.createBitmap(texture.width, texture.height, Bitmap.Config.ARGB_8888)
            defer { raw.recycle() }
            raw.copyPixelsFromBuffer(pixels)
            let flip = Matrix()
            flip.setScale(Float(1), Float(-1))
            output.set(Bitmap.createBitmap(raw, 0, 0, texture.width, texture.height, flip, false))
        } catch { self.error.set(String(describing: error)) }
    }
}
#endif
#endif
