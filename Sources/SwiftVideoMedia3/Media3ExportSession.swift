// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SKIP_BRIDGE
import Foundation

#if SKIP
import android.os.Handler
import android.os.Looper
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Typeface
import android.text.TextPaint
import android.text.StaticLayout
import android.text.Layout
import android.media.MediaExtractor
import android.media.MediaFormat
import androidx.media3.common.__
import androidx.media3.common.util.Size
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.effect.__
import androidx.media3.transformer.__
import java.io.File
import java.io.FileOutputStream
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
                let composition = try self.makeComposition(plan, folder: folder, sample: sample)
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
                    .addListener(ExportListener(completed: { self.finish(error: nil) }, failed: { message in self.finish(error: message) }))
                    .build()
                self.transformer = transformer
                transformer.start(composition, outputPath)
                self.poll()
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
        handler.post {
            if self.status.get() == 1 {
                self.transformer?.cancel()
                self.transformer = nil
                self.cleanup()
                self.status.set(-2)
            }
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

    private func makeComposition(_ plan: JSONObject, folder: File, sample: @escaping (String, Double) -> [Double]) throws -> Composition {
        let sequences = java.util.ArrayList<EditedMediaItemSequence>()
        let visualIDs = java.util.ArrayList<String>()
        let width = plan.getInt("width")
        let height = plan.getInt("height")
        let duration = plan.getLong("durationUs")
        let fps = Int(plan.getDouble("frameRate"))
        // An invisible full-duration primary image sequence supplies the output frame clock.
        let clear = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        clear.eraseColor(Color.TRANSPARENT)
        let clock = try saveBitmap(clear, name: "clock.png", folder: folder)
        sequences.add(imageSequence(clock, duration: duration, fps: fps, width: width, height: height))
        visualIDs.add("__clock")

        let clips = plan.getJSONArray("clips")
        var clipsWithAudio: Set<String> = []
        for index in 0..<clips.length() {
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            if kind == "video" || kind == "audio" {
                if try validateMedia(clip) { clipsWithAudio.insert(clip.getString("id")) }
            }
        }
        for index in 0..<clips.length() {
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            if kind == "audio" { continue }
            let start = clip.getLong("startUs")
            let length = clip.getLong("durationUs")
            let sourceStart = clip.getLong("sourceStartUs")
            let item: MediaItem
            if kind == "text" {
                let path = try textBitmap(clip, width: width, height: height, folder: folder)
                item = imageItem(path, duration: length)
            } else if kind == "image" {
                item = imageItem(clip.getString("url"), duration: length)
            } else {
                item = MediaItem.Builder().setUri(clip.getString("url"))
                    .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionUs(sourceStart)
                        .setEndPositionUs(sourceStart + length).build()).build()
            }
            let visualEffects = java.util.ArrayList<Effect>()
            let transform = clip.getJSONObject("transform")
            let crop = transform.getJSONObject("crop")
            visualEffects.add(Crop(Float(crop.getDouble("x") * 2 - 1), Float((crop.getDouble("x") + crop.getDouble("width")) * 2 - 1),
                                  Float(1 - (crop.getDouble("y") + crop.getDouble("height")) * 2), Float(1 - crop.getDouble("y") * 2)))
            let filters = clip.getJSONArray("filters")
            for filterIndex in 0..<filters.length() {
                let filter = filters.getJSONObject(filterIndex)
                if filter.getString("kind") == "blur" {
                    if filter.getDouble("value") > 0 { visualEffects.add(GaussianBlur(Float(filter.getDouble("value")))) }
                } else { visualEffects.add(ColorMatrixEffect(kind: filter.getString("kind"), value: filter.getDouble("value"))) }
            }
            let layout: Int
            switch transform.getString("contentMode") {
            case "fill": layout = Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
            case "stretch": layout = Presentation.LAYOUT_STRETCH_TO_FIT
            default: layout = Presentation.LAYOUT_SCALE_TO_FIT
            }
            visualEffects.add(Presentation.createForWidthAndHeight(max(1, Int(Double(width) * transform.getDouble("width"))),
                max(1, Int(Double(height) * transform.getDouble("height"))), layout))
            let edited = EditedMediaItem.Builder(item).setRemoveAudio(true).setFrameRate(fps)
                .setEffects(Effects(java.util.ArrayList<AudioProcessor>(), visualEffects)).build()
            let types = java.util.HashSet<Int>()
            types.add(C.TRACK_TYPE_VIDEO)
            let sequence = EditedMediaItemSequence.Builder(types)
            if start > 0 { sequence.addGap(start) }
            sequence.addItem(edited)
            if start + length < duration { sequence.addGap(duration - start - length) }
            sequences.add(sequence.build())
            visualIDs.add(clip.getString("id"))
        }
        let background = Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
        background.eraseColor(color(plan.getJSONObject("background")))
        let backgroundPath = try saveBitmap(background, name: "background.png", folder: folder)
        sequences.add(imageSequence(backgroundPath, duration: duration, fps: fps, width: width, height: height))
        visualIDs.add("__background")

        for index in 0..<clips.length() {
            let clip = clips.getJSONObject(index)
            if clip.getBoolean("muted") { continue }
            let kind = clip.getString("kind")
            if kind != "video" && kind != "audio" { continue }
            if !clipsWithAudio.contains(clip.getString("id")) { continue }
            let start = clip.getLong("startUs")
            let length = clip.getLong("durationUs")
            let sourceStart = clip.getLong("sourceStartUs")
            let item = MediaItem.Builder().setUri(clip.getString("url"))
                .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionUs(sourceStart)
                    .setEndPositionUs(sourceStart + length).build()).build()
            let processors = java.util.ArrayList<AudioProcessor>()
            processors.add(EnvelopeAudioProcessor(clip: clip))
            let edited = EditedMediaItem.Builder(item).setRemoveVideo(true)
                .setEffects(Effects(processors, java.util.ArrayList<Effect>())).build()
            let types = java.util.HashSet<Int>()
            types.add(C.TRACK_TYPE_AUDIO)
            let sequence = EditedMediaItemSequence.Builder(types)
            if start > 0 { sequence.addGap(start) }
            sequence.addItem(edited)
            if start + length < duration { sequence.addGap(duration - start - length) }
            sequences.add(sequence.build())
        }
        return Composition.Builder(sequences)
            .setVideoCompositorSettings(TimelineCompositor(width: width, height: height, ids: visualIDs, sample: sample))
            .setHdrMode(Composition.HDR_MODE_TONE_MAP_HDR_TO_SDR_USING_OPEN_GL).build()
    }

    private func validateMedia(_ clip: JSONObject) throws -> Bool {
        let extractor = MediaExtractor()
        defer { extractor.release() }
        extractor.setDataSource(ProcessInfo.processInfo.androidContext, Uri.parse(clip.getString("url")), nil)
        var videoDuration: Int64 = -1
        var audioDuration: Int64 = -1
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            let mime = format.getString(MediaFormat.KEY_MIME) ?? ""
            let duration = format.containsKey(MediaFormat.KEY_DURATION) ? format.getLong(MediaFormat.KEY_DURATION) : Int64(-1)
            if mime.hasPrefix("video/") { videoDuration = max(videoDuration, duration) }
            if mime.hasPrefix("audio/") { audioDuration = max(audioDuration, duration) }
        }
        let duration = clip.getString("kind") == "video" ? videoDuration : audioDuration
        guard duration >= clip.getLong("sourceStartUs") + clip.getLong("durationUs") else {
            throw IllegalArgumentException("Missing media track or source range exceeds its duration: " + clip.getString("id"))
        }
        return audioDuration >= 0
    }

    private func imageItem(_ path: String, duration: Int64) -> MediaItem {
        MediaItem.Builder().setUri(path).setImageDurationMs(max(Int64(1), (duration + 999) / 1000))
            .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setEndPositionUs(duration).build()).build()
    }

    private func imageSequence(_ path: String, duration: Int64, fps: Int, width: Int, height: Int) -> EditedMediaItemSequence {
        let effects = java.util.ArrayList<Effect>()
        effects.add(Presentation.createForWidthAndHeight(width, height, Presentation.LAYOUT_STRETCH_TO_FIT))
        let edited = EditedMediaItem.Builder(imageItem(path, duration: duration)).setDurationUs(duration).setFrameRate(fps)
            .setRemoveAudio(true).setEffects(Effects(java.util.ArrayList<AudioProcessor>(), effects)).build()
        let items = java.util.ArrayList<EditedMediaItem>()
        items.add(edited)
        return EditedMediaItemSequence.withVideoFrom(items)
    }

    private func textBitmap(_ clip: JSONObject, width: Int, height: Int, folder: File) throws -> String {
        let transform = clip.getJSONObject("transform")
        let textWidth = max(1, Int((Double(width) * transform.getDouble("width")).rounded()))
        let textHeight = max(1, Int((Double(height) * transform.getDouble("height")).rounded()))
        let bitmap = Bitmap.createBitmap(textWidth, textHeight, Bitmap.Config.ARGB_8888)
        let canvas = Canvas(bitmap)
        let style = clip.getJSONObject("textStyle")
        let paint = TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        paint.setTextSize(Float(style.getDouble("fontSize")))
        paint.setColor(color(style.getJSONObject("color")))
        if style.has("fontURL") {
            paint.setTypeface(Typeface.createFromFile(Uri.parse(style.getString("fontURL")).getPath()))
        } else if style.has("fontName") {
            paint.setTypeface(Typeface.create(style.getString("fontName"), Typeface.NORMAL))
        } else { paint.setTypeface(Typeface.DEFAULT) }
        if style.has("shadow") {
            let shadow = style.getJSONObject("shadow")
            paint.setShadowLayer(Float(shadow.getDouble("radius")), Float(shadow.getDouble("x")),
                                 Float(shadow.getDouble("y")), color(shadow.getJSONObject("color")))
        }
        let alignment: Layout.Alignment
        switch style.getString("alignment") {
        case "leading": alignment = Layout.Alignment.ALIGN_NORMAL
        case "trailing": alignment = Layout.Alignment.ALIGN_OPPOSITE
        default: alignment = Layout.Alignment.ALIGN_CENTER
        }
        let text = clip.getString("text")
        let layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, textWidth).setAlignment(alignment).setIncludePad(false).build()
        layout.draw(canvas)
        return try saveBitmap(bitmap, name: clip.getString("id") + ".png", folder: folder)
    }

    private func color(_ value: JSONObject) -> Int {
        Color.argb(Int(value.getDouble("alpha") * 255), Int(value.getDouble("red") * 255),
                   Int(value.getDouble("green") * 255), Int(value.getDouble("blue") * 255))
    }

    private func saveBitmap(_ bitmap: Bitmap, name: String, folder: File) throws -> String {
        defer { bitmap.recycle() }
        let file = File(folder, name)
        let stream = FileOutputStream(file)
        defer { stream.close() }
        guard bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) else { throw IllegalStateException("Cannot encode overlay image.") }
        return Uri.fromFile(file).toString()
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

private final class TimelineCompositor: VideoCompositorSettings {
    let width: Int
    let height: Int
    let ids: java.util.ArrayList<String>
    let sample: (String, Double) -> [Double]
    init(width: Int, height: Int, ids: java.util.ArrayList<String>, sample: @escaping (String, Double) -> [Double]) {
        self.width = width; self.height = height; self.ids = ids; self.sample = sample
    }
    override func getOutputSize(inputSizes: kotlin.collections.List<Size>) -> Size { Size(width, height) }
    override func getOverlaySettings(inputId: Int, presentationTimeUs: Int64) -> OverlaySettings {
        let id = ids.get(inputId)
        if id == "__clock" { return StaticOverlaySettings.Builder().setAlphaScale(Float(0)).build() }
        if id == "__background" { return StaticOverlaySettings.Builder().build() }
        let values = sample(id, Double(presentationTimeUs))
        return TimelineOverlay(values: values)
    }
}

/// Unclamped translation lets a layer animate across and beyond the canvas edge.
private final class TimelineOverlay: OverlaySettings {
    let values: [Double]
    init(values: [Double]) { self.values = values }
    override func getBackgroundFrameAnchor() -> android.util.Pair<Float, Float> {
        android.util.Pair.create(Float(values[0] * 2 - 1), Float(1 - values[1] * 2))
    }
    override func getScale() -> android.util.Pair<Float, Float> {
        android.util.Pair.create(Float(values[2]), Float(values[2]))
    }
    override func getRotationDegrees() -> Float { Float(-values[3]) }
    override func getAlphaScale() -> Float { Float(values[4]) }
}
#endif
#endif
