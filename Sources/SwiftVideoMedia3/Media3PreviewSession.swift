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
    private var surface: Surface?
    private var surfaceSize = Size(0, 0)
    private var wantsPlayback = false
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
                    self.rebuildPlayer()
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
            } else { self.player?.play() }
        }
        #endif
    }
    public func pause() {
        #if SKIP
        handler.post { self.wantsPlayback = false; self.player?.pause(); self.playing.set(false) }
        #endif
    }
    public func release() {
        #if SKIP
        cancelled.set(true)
        handler.post {
            self.player?.release()
            self.player = nil
            self.generation += 1
            self.composition = nil
            self.plan = nil
            self.surfaceView = nil
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
        handler.post {
            guard !self.cancelled.get() else { return }
            self.capturePosition()
            self.surfaceView = view
            self.surface = nil
            self.rebuildPlayer()
        }
    }
    // SKIP @nobridge
    public func detachSurfaceView(_ view: SurfaceView) {
        handler.post {
            guard self.surfaceView === view else { return }
            self.capturePosition()
            self.surfaceView = nil
            self.generation += 1
            self.player?.release()
            self.player = nil
        }
    }
    /// Native output surface integration, including offscreen pixel inspection.
    // SKIP @nobridge
    public func attachSurface(_ surface: Surface, width: Int, height: Int) {
        handler.post {
            guard !self.cancelled.get() else { return }
            self.capturePosition()
            self.surfaceView = nil
            self.surface = surface
            self.surfaceSize = Size(width, height)
            self.rebuildPlayer()
        }
    }

    private func clamped(_ value: Int64) -> Int64 { plan == nil ? max(0, value) : min(lastFramePosition, max(0, value)) }

    private func capturePosition() {
        if !seekPending { requestedPosition = clamped(player?.getCurrentPosition() ?? requestedPosition) }
        position.set(requestedPosition)
    }

    private func rebuildPlayer() {
        seekVersion += 1
        seekPending = false
        generation += 1
        let currentGeneration = generation
        player?.release()
        player = nil
        guard state.get() == 2, let composition, surfaceView != nil || surface != nil else { return }
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
            }))
            if let surfaceView, let plan {
                // Match the SDR frame writer before it starts dequeuing images.
                // Changing format after playback begins can close in-flight
                // ImageWriter images in Media3 1.12.0-alpha02.
                surfaceView.getHolder().setFormat(android.graphics.PixelFormat.RGBA_8888)
                surfaceView.getHolder().setFixedSize(plan.getInt("width"), plan.getInt("height"))
                player.setVideoSurfaceView(surfaceView)
            }
            else if let surface {
                player.setVideoSurfaceHolder(PreviewSurfaceHolder(surface: surface,
                    width: surfaceSize.getWidth(), height: surfaceSize.getHeight()))
            }
            player.setComposition(composition, requestedPosition)
            player.prepare()
            if wantsPlayback { player.play() }
        } catch { fail(String(describing: error)) }
    }
    private func pollPosition() {
        guard state.get() == 2 else { return }
        let current = seekPending ? requestedPosition : (player?.getCurrentPosition() ?? requestedPosition)
        if !seekPending, let player, !atEnd,
           player.getPlaybackState() == Player.STATE_ENDED || current >= durationMilliseconds {
            // Mixed sequences can reach the composition end before every internal
            // player reports ENDED. The project duration owns the transport limit.
            atEnd = true
            wantsPlayback = false
            player.pause()
        }
        position.set(atEnd ? durationMilliseconds : current)
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
/// Adapts a fixed offscreen surface to the holder required by Media3's frame writer.
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
    init(failed: @escaping (String) -> Void) { self.failed = failed }
    override func onPlayerError(error: PlaybackException) { failed(error.toString()) }
}
#endif
#endif
