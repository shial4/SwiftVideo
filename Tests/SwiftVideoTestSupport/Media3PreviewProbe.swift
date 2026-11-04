// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Canvas
import android.graphics.PixelFormat
import android.graphics.Rect
import android.media.ImageReader
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.media3.common.__
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.Size
import androidx.media3.effect.MultipleInputVideoGraph
import androidx.media3.effect.DefaultGlFrameProcessor
import androidx.media3.effect.Presentation
import androidx.media3.effect.StaticOverlaySettings
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.transformer.__
import SwiftVideoMedia3
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicIntegerArray
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicLongArray
import java.util.concurrent.atomic.AtomicReference
#endif

/// Test-only feasibility probe. Captures actual player output without exporting a movie.
public final class Media3PreviewProbe {
    #if SKIP
    private let handler = Handler(Looper.getMainLooper())
    private let state = AtomicInteger(0)
    private let failure = AtomicReference<String>("")
    private let count = AtomicInteger(0)
    private let samples = AtomicIntegerArray(6)
    private let firstFrameTime = AtomicLong(-1)
    private var player: CompositionPlayer?
    private var reader: ImageReader?
    private var viewHolder: PreviewProbeViewHolder?
    private var surfaceView: PreviewProbeSurfaceView?
    private var background: File?
    private var session: Media3PreviewSession?
    private let visualStats = AtomicIntegerArray(4)
    private let audioCounts = AtomicLongArray(3)
    private let audioSquares = AtomicLongArray(3)
    private let positionValue = AtomicLong(0)
    private var composition: Composition?
    private var seekMode = "seek"
    private var useFrameProcessor = false
    private let cancelled = AtomicBoolean(false)
    private var wantsPlayback = false
    #endif

    public init() {}

    public func start(imagePath: String, seekMode: String, useFrameProcessor: Bool = false) throws {
        #if SKIP
        guard state.compareAndSet(0, 1) else { throw IllegalStateException("Preview probe already started") }
        let started = SystemClock.elapsedRealtime()
        handler.post {
            do {
                self.seekMode = seekMode
                self.useFrameProcessor = useFrameProcessor
                let context = ProcessInfo.processInfo.androidContext
                let file = File.createTempFile("swiftvideo-preview-probe-", ".png", context.getCacheDir())
                self.background = file
                let bitmap = Bitmap.createBitmap(2, 2, Bitmap.Config.ARGB_8888)
                bitmap.eraseColor(Color.BLUE)
                do {
                    defer { bitmap.recycle() }
                    let stream = FileOutputStream(file)
                    defer { stream.close() }
                    guard bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) else {
                        throw IllegalStateException("Cannot create preview background")
                    }
                }
                let blue = Uri.fromFile(file).toString()
                let sequences = java.util.ArrayList<EditedMediaItemSequence>()
                // Match SwiftVideo's full-duration clock, independent layers, and gaps.
                sequences.add(self.sequence(path: blue, startUs: 0, durationUs: 18_000_000))
                sequences.add(self.sequence(path: imagePath, startUs: 5_000_000, durationUs: 3_000_000))
                sequences.add(self.sequence(path: blue, startUs: 0, durationUs: 18_000_000))
                let composition = Composition.Builder(sequences)
                    .setVideoCompositorSettings(PreviewProbeCompositor()).build()
                self.composition = composition
                let reader = self.makeReader(started: started, label: "seekMode=\(seekMode), frameProcessor=\(useFrameProcessor)")
                self.player = self.makePlayer(composition: composition, reader: reader, position: 0)
                self.pollPosition()
            } catch {
                self.failure.set(String(describing: error))
                self.state.set(-1)
            }
        }
        #endif
    }

    /// Captures the production preview session without replacing its renderer.
    public func start(json: String, useSurfaceView: Bool = false,
                      sample: @escaping @Sendable (String, Double) -> [Double]) throws {
        #if SKIP
        guard state.compareAndSet(0, 1) else { throw IllegalStateException("Preview probe already started") }
        let started = SystemClock.elapsedRealtime()
        let session = Media3PreviewSession()
        self.session = session
        let counts = audioCounts
        let squares = audioSquares
        session.audioSinkFactory = {
            for index in 0..<3 { counts.set(index, 0); squares.set(index, 0) }
            return PreviewAudioProbe(sink: DefaultAudioSink.Builder(ProcessInfo.processInfo.androidContext).build(),
                                     counts: counts, squares: squares)
        }
        handler.post {
            guard !self.cancelled.get() else { return }
            let reader = self.makeReader(started: started, label: "production composition")
            if useSurfaceView {
                let holder = PreviewProbeViewHolder(surface: reader.getSurface())
                let view = PreviewProbeSurfaceView(holder: holder)
                self.viewHolder = holder
                self.surfaceView = view
                session.attachSurfaceView(view)
            } else {
                session.attachSurface(reader.getSurface(), width: 320, height: 180)
            }
        }
        try session.start(json: json, sample: sample)
        #endif
    }

    /// Green count/centroid and white count/centroid. Centroids use 1/1000 pixels.
    public func spatialStats() -> [Int] {
        #if SKIP
        return (0..<4).map { visualStats.get($0) }
        #else
        return []
        #endif
    }

    public func seek(milliseconds: Int64) {
        #if SKIP
        if let session { session.seek(milliseconds: milliseconds); return }
        handler.post {
            if self.seekMode == "recreate", let composition = self.composition, let reader = self.reader {
                self.player?.release()
                self.player = self.makePlayer(composition: composition, reader: reader, position: milliseconds)
            } else if self.seekMode == "reset", let composition = self.composition {
                self.player?.setComposition(composition, milliseconds)
            } else {
                self.player?.seekTo(milliseconds)
            }
        }
        #endif
    }

    /// Replaces the output surface as a responsive layout would, keeping playback.
    public func replaceSurface(replaceView: Bool = false) {
        #if SKIP
        handler.post {
            guard !self.cancelled.get(), let session = self.session else { return }
            let previous = self.reader
            let reader = self.makeReader(started: SystemClock.elapsedRealtime(), label: "surface replacement")
            if let holder = self.viewHolder {
                let previousView = self.surfaceView
                if replaceView, let previousView { session.detachSurfaceView(previousView) }
                // Android destroys/recreates a view's surface on rotation. The
                // old producer must stop before surfaceDestroyed returns.
                holder.destroy()
                previous?.setOnImageAvailableListener(nil, nil)
                previous?.close()
                if replaceView {
                    let holder = PreviewProbeViewHolder(surface: reader.getSurface())
                    let view = PreviewProbeSurfaceView(holder: holder)
                    self.viewHolder = holder
                    self.surfaceView = view
                    session.attachSurfaceView(view)
                    // A late disposal of the old view must not detach the new one.
                    if let previousView { session.detachSurfaceView(previousView) }
                } else {
                    holder.create(surface: reader.getSurface())
                }
            } else {
                session.attachSurface(reader.getSurface(), width: 320, height: 180)
                // The offscreen API queues player release before the old reader closes.
                self.handler.post { previous?.close() }
            }
        }
        #endif
    }

    public func play() {
        #if SKIP
        if let session { session.play(); return }
        handler.post { self.wantsPlayback = true; self.player?.play() }
        #endif
    }

    public func pause() {
        #if SKIP
        if let session { session.pause(); return }
        handler.post { self.wantsPlayback = false; self.player?.pause() }
        #endif
    }

    public func positionMilliseconds() -> Int64 {
        #if SKIP
        return session?.positionMilliseconds() ?? positionValue.get()
        #else
        return 0
        #endif
    }

    public func isPlaying() -> Bool {
        #if SKIP
        return session?.isPlaying() ?? false
        #else
        return false
        #endif
    }

    public func audioRMS() -> [Double] {
        #if SKIP
        return (0..<3).map {
            let count = audioCounts.get($0)
            return count > 0 ? sqrt(Double(audioSquares.get($0)) / Double(count)) / 32768 : -1.0
        }
        #else
        return []
        #endif
    }

    public func status() -> Int {
        #if SKIP
        return session?.currentStatus() ?? state.get()
        #else
        return -1
        #endif
    }

    public func temporaryDirectoryPath() -> String {
        #if SKIP
        return session?.temporaryDirectoryPath() ?? ""
        #else
        return ""
        #endif
    }

    public func frameCount() -> Int {
        #if SKIP
        return count.get()
        #else
        return 0
        #endif
    }

    public func pixels() -> [Int] {
        #if SKIP
        return (0..<6).map { samples.get($0) }
        #else
        return []
        #endif
    }

    public func firstFrameMilliseconds() -> Int64 {
        #if SKIP
        return firstFrameTime.get()
        #else
        return -1
        #endif
    }

    public func failureMessage() -> String {
        #if SKIP
        return session?.failureMessage() ?? failure.get()
        #else
        return "Android preview probe is unavailable"
        #endif
    }

    public func release() {
        #if SKIP
        cancelled.set(true)
        session?.release()
        handler.post {
            self.player?.release()
            self.player = nil
            self.composition = nil
            self.reader?.close()
            self.reader = nil
            self.viewHolder = nil
            self.surfaceView = nil
            self.background?.delete()
            self.background = nil
            self.state.set(3)
        }
        #endif
    }

    #if SKIP
    private func pollPosition() {
        guard state.get() == 1 else { return }
        positionValue.set(player?.getCurrentPosition() ?? 0)
        handler.postDelayed({ self.pollPosition() }, Int64(50))
    }

    private func makeReader(started: Int64, label: String) -> ImageReader {
        let reader = ImageReader.newInstance(320, 180, PixelFormat.RGBA_8888, 3)
        self.reader = reader
        reader.setOnImageAvailableListener({ source in
            guard let image = source.acquireLatestImage() else { return }
            defer { image.close() }
            let plane = image.getPlanes()[0]
            let bytes = plane.getBuffer()
            for point in 0..<2 {
                let x = point == 0 ? 160 : 8
                let offset = 90 * plane.getRowStride() + x * plane.getPixelStride()
                for channel in 0..<3 {
                    self.samples.set(point * 3 + channel, Int(bytes.get(offset + channel)) & 255)
                }
            }
            var greenCount = 0
            var greenX = 0
            var whiteCount = 0
            var whiteX = 0
            for y in 0..<180 {
                for x in 0..<320 {
                    let offset = y * plane.getRowStride() + x * plane.getPixelStride()
                    let r = Int(bytes.get(offset)) & 255
                    let g = Int(bytes.get(offset + 1)) & 255
                    let b = Int(bytes.get(offset + 2)) & 255
                    if g > 200 && r < 50 && b < 50 { greenCount += 1; greenX += x }
                    if r > 200 && g > 200 && b > 200 { whiteCount += 1; whiteX += x }
                }
            }
            self.visualStats.set(0, greenCount)
            self.visualStats.set(1, greenCount > 0 ? greenX * 1000 / greenCount : -1)
            self.visualStats.set(2, whiteCount)
            self.visualStats.set(3, whiteCount > 0 ? whiteX * 1000 / whiteCount : -1)
            let elapsed = SystemClock.elapsedRealtime() - started
            if self.firstFrameTime.compareAndSet(-1, elapsed) {
                Log.i("SwiftVideoPreviewProbe", "First surface frame: " + String(elapsed) + " ms; " + label)
            }
            self.count.incrementAndGet()
        }, handler)
        return reader
    }

    private func makePlayer(composition: Composition, reader: ImageReader, position: Int64) -> CompositionPlayer {
        for index in 0..<3 { audioCounts.set(index, 0); audioSquares.set(index, 0) }
        positionValue.set(position)
        let builder = CompositionPlayer.Builder(ProcessInfo.processInfo.androidContext)
            .setLooper(Looper.getMainLooper())
            .setAudioSink(PreviewAudioProbe(sink: DefaultAudioSink.Builder(ProcessInfo.processInfo.androidContext).build(),
                                           counts: audioCounts, squares: audioSquares))
        if useFrameProcessor {
            builder.setFrameProcessorFactory(DefaultGlFrameProcessor.Factory.Builder(ProcessInfo.processInfo.androidContext).build())
        } else {
            builder.setVideoGraphFactory(MultipleInputVideoGraph.Factory())
        }
        let player = builder.build()
        player.addListener(PreviewProbeListener(failed: { message in
            self.failure.set(message)
            self.state.set(-1)
        }))
        if useFrameProcessor {
            player.setVideoSurfaceHolder(PreviewProbeViewHolder(surface: reader.getSurface()))
        } else {
            player.setVideoSurface(reader.getSurface(), Size(320, 180))
        }
        player.setComposition(composition, position)
        player.prepare()
        if wantsPlayback { player.play() }
        return player
    }

    private func sequence(path: String, startUs: Int64, durationUs: Int64) -> EditedMediaItemSequence {
        let item = MediaItem.Builder().setUri(path).setImageDurationMs(durationUs / 1000).build()
        let effects = java.util.ArrayList<Effect>()
        effects.add(Presentation.createForWidthAndHeight(320, 180, Presentation.LAYOUT_STRETCH_TO_FIT))
        let edited = EditedMediaItem.Builder(item).setDurationUs(durationUs).setFrameRate(30).setRemoveAudio(true)
            .setEffects(Effects(java.util.ArrayList<AudioProcessor>(), effects)).build()
        let types = java.util.HashSet<Int>()
        types.add(C.TRACK_TYPE_VIDEO)
        let sequence = EditedMediaItemSequence.Builder(types)
        if startUs > 0 { sequence.addGap(startUs) }
        sequence.addItem(edited)
        if startUs + durationUs < 18_000_000 { sequence.addGap(18_000_000 - startUs - durationUs) }
        return sequence.build()
    }
    #endif
}

#if SKIP
/// A real SurfaceView API boundary backed by captured buffers, with controllable
/// holder events instead of a test Activity or an authored Android manifest.
private final class PreviewProbeSurfaceView: SurfaceView {
    private let outputHolder: PreviewProbeViewHolder
    init(holder: PreviewProbeViewHolder) {
        self.outputHolder = holder
        super.init(ProcessInfo.processInfo.androidContext)
    }
    override func getHolder() -> SurfaceHolder { outputHolder }
}

private final class PreviewProbeViewHolder: SurfaceHolder {
    private var outputSurface: Surface
    private let handler = Handler(Looper.getMainLooper())
    private let callbacks = java.util.ArrayList<SurfaceHolder.Callback>()
    private var width = 320
    private var height = 180
    private var pixelFormat = PixelFormat.RGBA_8888
    init(surface: Surface) { self.outputSurface = surface }
    func destroy() {
        for callback in java.util.ArrayList(callbacks) { callback.surfaceDestroyed(self) }
    }
    func create(surface: Surface) {
        self.outputSurface = surface
        for callback in java.util.ArrayList(callbacks) {
            callback.surfaceCreated(self)
            callback.surfaceChanged(self, PixelFormat.RGBA_8888, 320, 180)
        }
    }
    override func addCallback(callback: SurfaceHolder.Callback) { callbacks.add(callback); return }
    override func removeCallback(callback: SurfaceHolder.Callback) { callbacks.remove(callback); return }
    override func getSurface() -> Surface { outputSurface }
    override func getSurfaceFrame() -> Rect { Rect(0, 0, width, height) }
    override func isCreating() -> Bool { false }
    override func setType(type: Int) {}
    override func setKeepScreenOn(keepScreenOn: Bool) {}
    override func setSizeFromLayout() {}
    override func setFixedSize(width: Int, height: Int) {
        self.width = width
        self.height = height
        changed()
    }
    override func setFormat(format: Int) { self.pixelFormat = format; changed() }
    override func lockCanvas() -> Canvas { throw UnsupportedOperationException("Captured surface") }
    override func lockCanvas(dirty: Rect?) -> Canvas { throw UnsupportedOperationException("Captured surface") }
    override func unlockCanvasAndPost(canvas: Canvas) { throw UnsupportedOperationException("Captured surface") }
    private func changed() {
        handler.post {
            for callback in java.util.ArrayList(self.callbacks) {
                callback.surfaceChanged(self, self.pixelFormat, self.width, self.height)
            }
        }
    }
}
#endif

#if SKIP
private final class PreviewProbeListener: Player.Listener {
    let failed: (String) -> Void
    init(failed: @escaping (String) -> Void) { self.failed = failed }
    override func onPlayerError(error: PlaybackException) { failed(error.toString()) }
}

private final class PreviewProbeCompositor: VideoCompositorSettings {
    override func getOutputSize(inputSizes: kotlin.collections.List<Size>) -> Size { Size(320, 180) }
    override func getOverlaySettings(inputId: Int, presentationTimeUs: Int64) -> OverlaySettings {
        if inputId == 0 { return StaticOverlaySettings.Builder().setAlphaScale(Float(0)).build() }
        if inputId == 1 {
            // Gap frames are black, so match SwiftVideo's time-range opacity guard.
            let visible = presentationTimeUs >= 5_000_000 && presentationTimeUs < 8_000_000
            return StaticOverlaySettings.Builder().setScale(Float(0.5), Float(0.5))
                .setAlphaScale(visible ? Float(1) : Float(0)).build()
        }
        return StaticOverlaySettings.Builder().build()
    }
}
#endif
#endif
