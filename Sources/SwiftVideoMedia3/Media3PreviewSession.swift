// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation
#if SKIP
import android.os.Handler
import android.os.Looper
import android.view.Surface
import android.view.SurfaceView
import android.view.SurfaceHolder
import android.graphics.Canvas
import android.graphics.Rect
import androidx.media3.common.__
import androidx.media3.common.util.Size
import androidx.media3.effect.DefaultGlFrameProcessor
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.source.DefaultMediaSourceFactory
import androidx.media3.transformer.__
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
#endif

/// Direct Android playback of the same composition used for export.
/// Player and surface operations run on the main looper; preparation runs off it.
public final class Media3PreviewSession {
    #if SKIP
    private let handler = Handler(Looper.getMainLooper())
    private let state = AtomicInteger(0)
    private let failure = AtomicReference<String>("")
    private let position = AtomicLong(0)
    private let playing = AtomicBoolean(false)
    private let cancelled = AtomicBoolean(false)
    private let preparing = AtomicBoolean(false)
    private let scratchPath = AtomicReference<String>("")
    private var player: CompositionPlayer?
    private var composition: Composition?
    private var plan: JSONObject?
    private var folder: File?
    private var surfaceView: SurfaceView?
    private var surfaceCallback: PreviewSurfaceCallback?
    private var surface: Surface?
    private var surfaceSize = Size(0, 0)
    private var wantsPlayback = false
    private var hasRenderedFirstFrame = false
    private var requestedPosition: Int64 = 0
    private var lastFramePosition: Int64 = 0
    private var durationMilliseconds: Int64 = 0
    private var generation = 0
    private var seekVersion = 0
    private var seekPending = false
    private var atEnd = false

    /// Optional native audio output integration, also used for PCM inspection.
    // SKIP @nobridge
    public var audioSinkFactory: (() -> AudioSink)?
    #endif

    public init() {}

    public func start(json: String, sample: @escaping @Sendable (String, Double) -> [Double]) throws {
        #if SKIP
        guard !cancelled.get(), state.compareAndSet(0, 1) else { throw IllegalStateException("Preview session already started or released") }
        preparing.set(true)
        java.lang.Thread({
            let directory = File(ProcessInfo.processInfo.androidContext.getCacheDir(), "swiftvideo-preview-" + UUID().uuidString)
            self.scratchPath.set(directory.getAbsolutePath())
            do {
                guard directory.mkdirs() else { throw IllegalStateException("Cannot create preview scratch directory") }
                let plan = try Media3PreviewAudioCache(folder: directory).prepare(JSONObject(json), cancelled: { self.cancelled.get() })
                let composition = try Media3CompositionBuilder().build(plan, folder: directory, sample: sample)
                self.handler.post {
                    self.preparing.set(false)
                    if self.cancelled.get() {
                        self.deleteFolder(directory)
                        self.state.set(3)
                        return
                    }
                    self.folder = directory
                    self.plan = plan
                    self.composition = composition
                    let durationUs = plan.getLong("durationUs")
                    self.durationMilliseconds = durationUs / 1000 + (durationUs % 1000 == Int64(0) ? 0 : 1)
                    let frames = max(0.0, floor(Double(plan.getLong("durationUs") - 1) * plan.getDouble("frameRate") / 1_000_000))
                    self.lastFramePosition = Int64(frames * 1000 / plan.getDouble("frameRate"))
                    self.requestedPosition = self.clamped(self.requestedPosition)
                    self.state.set(2)
                    if let view = self.surfaceView { self.configureSurfaceView(view) }
                    else { self.rebuildPlayer() }
                    self.pollPosition()
                }
            } catch {
                self.handler.post {
                    self.preparing.set(false)
                    self.deleteFolder(directory)
                    if self.cancelled.get() { self.state.set(3) }
                    else { self.fail(String(describing: error)) }
                }
            }
        }, "SwiftVideo preview preparation").start()
        #else
        throw NSError(domain: "SwiftVideo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Direct Media3 preview requires Android."])
        #endif
    }

    /// 0 idle, 1 preparing, 2 prepared, 3 released, -1 failed.
    public func currentStatus() -> Int {
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
        return "Direct Media3 preview requires Android."
        #endif
    }
    public func positionMilliseconds() -> Int64 {
        #if SKIP
        return position.get()
        #else
        return 0
        #endif
    }
    /// Playback intent, retained while a surface is replaced or a player buffers.
    public func isPlaying() -> Bool {
        #if SKIP
        return playing.get()
        #else
        return false
        #endif
    }
    public func temporaryDirectoryPath() -> String {
        #if SKIP
        return scratchPath.get()
        #else
        return ""
        #endif
    }
    public func seek(milliseconds: Int64) {
        #if SKIP
        handler.post {
            guard !self.cancelled.get(), self.state.get() >= 0 else { return }
            self.requestedPosition = self.plan == nil ? max(0, milliseconds) : self.clamped(milliseconds)
            self.atEnd = false
            self.position.set(self.requestedPosition)
            self.player?.pause()
            self.playing.set(false)
            self.seekPending = true
            self.seekVersion += 1
            let version = self.seekVersion
            self.handler.postDelayed({
                guard !self.cancelled.get(), self.seekVersion == version else { return }
                self.rebuildPlayer()
            }, Int64(16))
        }
        #endif
    }
    public func play() {
        #if SKIP
        handler.post {
            guard !self.cancelled.get(), self.state.get() >= 0 else { return }
            self.wantsPlayback = true
            if self.seekPending { return }
            if self.atEnd || self.player?.getPlaybackState() == Player.STATE_ENDED {
                self.requestedPosition = 0
                self.atEnd = false
                self.rebuildPlayer()
            } else if self.hasRenderedFirstFrame { self.player?.play() }
        }
        #endif
    }
    public func pause() {
        #if SKIP
        handler.post {
            self.wantsPlayback = false
            self.player?.pause()
            self.capturePosition()
            self.playing.set(false)
        }
        #endif
    }
    public func release() {
        #if SKIP
        cancelled.set(true)
        onMain {
            self.clearSurfaceView()
            self.releasePlayer()
            self.composition = nil
            self.plan = nil
            self.surface = nil
            self.playing.set(false)
            self.deleteFolder(self.folder)
            self.folder = nil
            self.audioSinkFactory = nil
            if !self.preparing.get() { self.state.set(3) }
        }
        #endif
    }

    #if SKIP
    // SKIP @nobridge
    public func attachSurfaceView(_ view: SurfaceView) {
        onMain {
            guard !self.cancelled.get(), self.surfaceView !== view else { return }
            self.capturePosition()
            self.clearSurfaceView()
            self.releasePlayer()
            self.surfaceView = view
            self.surface = nil
            let callback = PreviewSurfaceCallback(changed: { holder, format, width, height in
                self.updateViewSurface(holder, format: format, width: width, height: height)
            }, destroyed: { holder in
                guard self.surfaceView?.getHolder() === holder else { return }
                self.capturePosition()
                self.surface = nil
                // SurfaceHolder requires all drawing to stop before this callback
                // returns. Release the frame processor before its writer closes.
                self.releasePlayer()
            })
            self.surfaceCallback = callback
            view.getHolder().addCallback(callback)
            self.configureSurfaceView(view)
        }
    }
    // SKIP @nobridge
    public func detachSurfaceView(_ view: SurfaceView) {
        onMain {
            guard self.surfaceView === view else { return }
            self.capturePosition()
            self.clearSurfaceView()
            self.surface = nil
            self.releasePlayer()
        }
    }
    /// Native output surface integration, including offscreen pixel inspection.
    // SKIP @nobridge
    public func attachSurface(_ surface: Surface, width: Int, height: Int) {
        onMain {
            guard !self.cancelled.get() else { return }
            self.capturePosition()
            self.clearSurfaceView()
            self.surface = surface
            self.surfaceSize = Size(width, height)
            self.rebuildPlayer()
        }
    }

    private func onMain(_ action: @escaping () -> Void) {
        if Looper.myLooper() === Looper.getMainLooper() { action() }
        else { handler.post { action() } }
    }

    private func clearSurfaceView() {
        if let surfaceCallback { surfaceView?.getHolder().removeCallback(surfaceCallback) }
        surfaceCallback = nil
        surfaceView = nil
    }

    private func configureSurfaceView(_ view: SurfaceView) {
        guard let plan else { return }
        let holder = view.getHolder()
        holder.setFormat(android.graphics.PixelFormat.RGBA_8888)
        holder.setFixedSize(plan.getInt("width"), plan.getInt("height"))
        let frame = holder.getSurfaceFrame()
        updateViewSurface(holder, format: android.graphics.PixelFormat.RGBA_8888,
                          width: frame.width(), height: frame.height())
    }

    private func updateViewSurface(_ holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        guard !cancelled.get(), surfaceView?.getHolder() === holder, let plan else { return }
        let output = holder.getSurface()
        let ready = output.isValid() && format == android.graphics.PixelFormat.RGBA_8888
            && width == plan.getInt("width") && height == plan.getInt("height")
        capturePosition()
        surface = ready ? output : nil
        surfaceSize = Size(width, height)
        rebuildPlayer()
    }

    private func clamped(_ value: Int64) -> Int64 { plan == nil ? max(0, value) : min(lastFramePosition, max(0, value)) }

    private func capturePosition() {
        if !seekPending { requestedPosition = clamped(player?.getCurrentPosition() ?? requestedPosition) }
        position.set(requestedPosition)
    }

    private func rebuildPlayer() {
        seekVersion += 1
        seekPending = false
        releasePlayer()
        let currentGeneration = generation
        guard state.get() == 2, let composition, let surface else { return }
        do {
            let builder = CompositionPlayer.Builder(ProcessInfo.processInfo.androidContext)
                .setLooper(Looper.getMainLooper())
                .setMediaSourceFactory(DefaultMediaSourceFactory(ProcessInfo.processInfo.androidContext,
                    PcmBoundaryExtractorsFactory(boundaries: pcmBoundaries(positionUs: requestedPosition * 1000)))
                    .setEnableClippingInMediaPeriod(true))
                .setFrameProcessorFactory(DefaultGlFrameProcessor.Factory.Builder(ProcessInfo.processInfo.androidContext).build())
            if let audioSinkFactory { builder.setAudioSink(audioSinkFactory()) }
            let player = builder.build()
            self.player = player
            player.addListener(PreviewSessionListener(failed: { message in
                if self.generation == currentGeneration && !self.cancelled.get() { self.fail(message) }
            }, renderedFirstFrame: {
                guard self.generation == currentGeneration, !self.cancelled.get() else { return }
                self.hasRenderedFirstFrame = true
                if self.wantsPlayback && !self.seekPending && !self.atEnd { self.player?.play() }
            }))
            // Keep Media3's format negotiation on a fixed holder. The session
            // owns view callbacks and drains the old player before replacing
            // its surface, avoiding writer closure with a GPU frame in flight.
            player.setVideoSurfaceHolder(PreviewSurfaceHolder(surface: surface,
                width: surfaceSize.getWidth(), height: surfaceSize.getHeight()))
            player.setComposition(composition, requestedPosition)
            player.prepare()
            // Prepare the first paused frame before starting the clock. Otherwise
            // a short timeline can end and pause before its first GPU output.
        } catch { fail(String(describing: error)) }
    }

    private func releasePlayer() {
        generation += 1
        player?.release()
        player = nil
        hasRenderedFirstFrame = false
    }
    private func pollPosition() {
        guard state.get() == 2 else { return }
        let current = seekPending ? requestedPosition : (player?.getCurrentPosition() ?? requestedPosition)
        if !seekPending, let player, !atEnd,
           player.getPlaybackState() == Player.STATE_ENDED {
            // The clock can reach the end while GPU output is still pending.
            // Let Media3 drain that output before completing the transport.
            atEnd = true
            wantsPlayback = false
            player.pause()
        }
        position.set(atEnd ? durationMilliseconds : min(durationMilliseconds, current))
        playing.set(!seekPending && !atEnd && wantsPlayback)
        handler.postDelayed({ self.pollPosition() }, Int64(33))
    }
    private func pcmBoundaries(positionUs: Int64) -> [String: [Int64]] {
        guard let clips = plan?.getJSONArray("clips") else { return [:] }
        var boundaries: [String: [Int64]] = [:]
        for index in 0..<clips.length() {
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            if kind != "audio" && kind != "video" { continue }
            let start = clip.optLong("audioSourceStartUs", clip.getLong("sourceStartUs"))
            let duration = clip.getLong("durationUs")
            let seek = min(duration, max(Int64(0), positionUs - clip.getLong("startUs")))
            let url = clip.optString("audioURL", clip.getString("url"))
            boundaries[url] = Array(Set((boundaries[url] ?? []) + [start, start + duration, start + seek])).sorted()
        }
        return boundaries
    }
    private func fail(_ message: String) {
        generation += 1
        failure.set(message)
        state.set(-1)
        playing.set(false)
        player?.release()
        player = nil
        composition = nil
        deleteFolder(folder)
        folder = nil
    }
    private func deleteFolder(_ directory: File?) {
        if let files = directory?.listFiles() { for file in files { file.delete() } }
        directory?.delete()
    }
    #endif
}

#if SKIP
private final class PreviewSurfaceCallback: SurfaceHolder.Callback {
    private let changed: (SurfaceHolder, Int, Int, Int) -> Void
    private let destroyed: (SurfaceHolder) -> Void
    init(changed: @escaping (SurfaceHolder, Int, Int, Int) -> Void,
         destroyed: @escaping (SurfaceHolder) -> Void) {
        self.changed = changed
        self.destroyed = destroyed
    }
    override func surfaceCreated(holder: SurfaceHolder) {}
    override func surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        changed(holder, format, width, height)
    }
    override func surfaceDestroyed(holder: SurfaceHolder) { destroyed(holder) }
}

/// Adapts a fixed surface to the holder required by Media3's frame writer.
private final class PreviewSurfaceHolder: SurfaceHolder {
    private let surface: Surface
    private let handler = Handler(Looper.getMainLooper())
    private let callbacks = java.util.ArrayList<SurfaceHolder.Callback>()
    private var width: Int
    private var height: Int
    private var pixelFormat = android.graphics.PixelFormat.RGBA_8888
    init(surface: Surface, width: Int, height: Int) {
        self.surface = surface
        self.width = width
        self.height = height
    }
    override func addCallback(callback: SurfaceHolder.Callback) { callbacks.add(callback); return }
    override func removeCallback(callback: SurfaceHolder.Callback) { callbacks.remove(callback); return }
    override func getSurface() -> Surface { surface }
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
    override func lockCanvas() -> Canvas { throw UnsupportedOperationException("Offscreen surface") }
    override func lockCanvas(dirty: Rect?) -> Canvas { throw UnsupportedOperationException("Offscreen surface") }
    override func unlockCanvasAndPost(canvas: Canvas) { throw UnsupportedOperationException("Offscreen surface") }
    private func changed() {
        handler.post {
            for callback in self.callbacks {
                callback.surfaceChanged(self, self.pixelFormat, self.width, self.height)
            }
        }
    }
}

private final class PreviewSessionListener: Player.Listener {
    private let failed: (String) -> Void
    private let renderedFirstFrame: () -> Void
    init(failed: @escaping (String) -> Void, renderedFirstFrame: @escaping () -> Void) {
        self.failed = failed
        self.renderedFirstFrame = renderedFirstFrame
    }
    override func onPlayerError(error: PlaybackException) { failed(error.toString()) }
    override func onRenderedFirstFrame() { renderedFirstFrame() }
}
#endif
#endif
