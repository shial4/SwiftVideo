// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation

#if SKIP
import android.os.Handler
import android.os.Looper
import androidx.media3.common.__
import androidx.media3.transformer.__
import java.io.File
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicReference
import org.json.JSONObject
#endif

/// Internal service API. Transformer and temporary bitmaps are confined to Android's main looper.
/// Only atomic status/progress values are read from native Swift's exporter actor.
public final class Media3ExportSession {
    #if SKIP
    private let handler = Handler(Looper.getMainLooper())
    private let status = AtomicInteger(0)
    private let progressValue = AtomicInteger(0)
    private let errorText = AtomicReference<String>("")
    private var transformer: Transformer?
    private var directory: File?
    private var preparing = false
    private let cancellationRequested = AtomicBoolean(false)
    #endif

    public init() throws {
        #if SKIP
        // Native Swift can enter this service before the JVM has registered the
        // callback library. Loading through Java makes its JNI callbacks visible.
        java.lang.System.loadLibrary("SkipBridge")
        #else
        throw NSError(domain: "SwiftVideoMedia3", code: 1, userInfo: [NSLocalizedDescriptionKey: "Media3 is available only through the Android Skip bridge."])
        #endif
    }

    public func start(json: String, outputPath: String, sample: @escaping @Sendable (String, Double) -> [Double]) throws {
        #if SKIP
        guard status.compareAndSet(0, 1) else { throw IllegalStateException("An export session can only start once.") }
        handler.post {
            do {
                let plan = JSONObject(json)
                let context = ProcessInfo.processInfo.androidContext
                let folder = File(context.getCacheDir(), "swiftvideo-" + UUID().uuidString)
                guard folder.mkdirs() else { throw IllegalStateException("Cannot create export scratch directory.") }
                self.directory = folder
                self.preparing = true
                java.lang.Thread {
                    var prepared: JSONObject?
                    var failure: String?
                    do {
                        prepared = try Media3PCMTrimmer().prepare(plan, folder: folder,
                            cancelled: { self.cancellationRequested.get() })
                    } catch { failure = String(describing: error) }
                    self.handler.post {
                        self.preparing = false
                        if self.cancellationRequested.get() { self.finishCancellation() }
                        else if let failure { self.finish(error: failure) }
                        else if let prepared {
                            do { try self.beginExport(prepared, folder: folder, outputPath: outputPath, sample: sample) }
                            catch { self.finish(error: String(describing: error)) }
                        }
                    }
                }.start()
            } catch { self.finish(error: String(describing: error)) }
        }
        #else
        throw unavailable()
        #endif
    }

    public func currentStatus() throws -> Int {
        #if SKIP
        return status.get()
        #else
        throw unavailable()
        #endif
    }

    public func currentProgress() throws -> Double {
        #if SKIP
        return Double(progressValue.get()) / 100
        #else
        throw unavailable()
        #endif
    }

    public func failureMessage() throws -> String {
        #if SKIP
        return errorText.get()
        #else
        throw unavailable()
        #endif
    }

    public func cancel() throws {
        #if SKIP
        cancellationRequested.set(true)
        handler.post {
            if self.status.get() == 1 && !self.preparing { self.finishCancellation() }
        }
        #else
        throw unavailable()
        #endif
    }

    #if !SKIP
    private func unavailable() -> NSError {
        NSError(domain: "SwiftVideoMedia3", code: 1, userInfo: [NSLocalizedDescriptionKey: "No Android runtime is available."])
    }
    #endif

    #if SKIP
    private func beginExport(_ plan: JSONObject, folder: File, outputPath: String,
                             sample: @escaping (String, Double) -> [Double]) throws {
        let context = ProcessInfo.processInfo.androidContext
        let composition = try Media3CompositionBuilder().build(plan, folder: folder, sample: sample)
        let encoder = DefaultEncoderFactory.Builder(context)
            .setEnableFallback(false)
            .setRequestedVideoEncoderSettings(VideoEncoderSettings.Builder().setBitrate(plan.getInt("videoBitRate")).build())
            .setRequestedAudioEncoderSettings(AudioEncoderSettings.Builder().setBitrate(plan.getInt("audioBitRate")).build())
            .build()
        let transformer = Transformer.Builder(context)
            .setLooper(Looper.getMainLooper())
            .setVideoMimeType(plan.getString("codec") == "hevc" ? MimeTypes.VIDEO_H265 : MimeTypes.VIDEO_H264)
            .setAudioMimeType(MimeTypes.AUDIO_AAC)
            .setEncoderFactory(encoder)
            // A single frame has no previous sample from which the muxer
            // can infer its duration. The composition owns the endpoint.
            .setMuxerFactory(TimelineMuxerFactory(durationUs: plan.getLong("durationUs")))
            .addListener(ExportListener(completed: { self.finish(error: nil) }, failed: { message in self.finish(error: message) }))
            .build()
        self.transformer = transformer
        transformer.start(composition, outputPath)
        self.poll()
    }

    private func finishCancellation() {
        transformer?.cancel()
        transformer = nil
        cleanup()
        status.set(-2)
    }

    private func poll() {
        guard status.get() == 1, let transformer else { return }
        let holder = ProgressHolder()
        if transformer.getProgress(holder) == Transformer.PROGRESS_STATE_AVAILABLE {
            progressValue.set(max(progressValue.get(), holder.progress))
        }
        handler.postDelayed({ self.poll() }, Int64(100))
    }

    private func finish(error: String?) {
        guard status.get() == 1 else { return }
        if let error {
            errorText.set(error)
            transformer?.cancel()
        }
        transformer = nil
        cleanup()
        status.set(error == nil ? 2 : -1)
    }

    private func cleanup() {
        if let files = directory?.listFiles() { for file in files { file.delete() } }
        directory?.delete()
        directory = nil
    }
    #endif
}

#if SKIP
private final class ExportListener: Transformer.Listener {
    let completed: () -> Void
    let failed: (String) -> Void
    init(completed: @escaping () -> Void, failed: @escaping (String) -> Void) { self.completed = completed; self.failed = failed }
    override func onCompleted(composition: Composition, exportResult: ExportResult) { completed() }
    override func onError(composition: Composition, exportResult: ExportResult, exportException: ExportException) {
        failed(exportException.toString() + "; code=" + String(exportException.errorCode)
            + "; cause=" + (exportException.cause?.toString() ?? "unknown"))
    }
}

#endif
#endif
