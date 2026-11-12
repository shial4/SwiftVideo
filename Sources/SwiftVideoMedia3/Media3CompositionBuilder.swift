// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.net.Uri
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.text.StaticLayout
import android.media.MediaExtractor
import android.media.MediaFormat
import androidx.media3.common.__
import androidx.media3.common.util.Size
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.effect.__
import androidx.media3.transformer.__
import java.io.File
import org.json.JSONObject

/// Shared Android composition construction for export and preview. The caller owns
/// the scratch directory and must retain it until its player or exporter releases.
// SKIP @nobridge
public final class Media3CompositionBuilder {
    public init() {}

    public func build(_ plan: JSONObject, folder: File, sample: @escaping (String, Double) -> [Double],
                      audio: @escaping (String, Int, Int, Data, Bool) throws -> Data = { _, _, _, _, _ in
                          throw IllegalArgumentException("Custom audio requires an export effect registry.")
                      },
                      visual: @escaping (String, Int) throws -> Media3VisualEffect = { _, _ in
                          throw IllegalArgumentException("Native visual effects require an export effect registry.")
                      },
                      titleMotion: @escaping (String, Double) throws -> Data = { _, _ in
                          throw IllegalArgumentException("Motion titles are not supported by direct preview.")
                      }) throws -> Composition {
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
        var mediaTiming: [String: MediaTiming] = [:]
        for index in 0..<clips.length() {
            let clip = clips.getJSONObject(index)
            let kind = clip.getString("kind")
            if kind == "video" || kind == "audio" {
                mediaTiming[clip.getString("id")] = try validateMedia(clip)
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
            var motionRaster: MotionTitleRaster? = nil
            if kind == "text" {
                let path: String
                if clip.has("textMotion") {
                    let raster = try Media3TextRaster.motion(clip, width: width, height: height, folder: folder)
                    motionRaster = raster; path = raster.path
                } else { path = try textBitmap(clip, width: width, height: height, folder: folder) }
                item = imageItem(path, duration: length)
            } else if kind == "image" {
                item = imageItem(clip.getString("url"), duration: length)
            } else {
                item = MediaItem.Builder().setUri(clip.getString("url"))
                    .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionUs(sourceStart)
                        .setEndPositionUs(sourceStart + clip.getLong("sourceDurationUs")).build()).build()
            }
            let visualEffects = java.util.ArrayList<Effect>()
            if let raster = motionRaster { visualEffects.add(MotionTitleEffect(raster: raster, sample: titleMotion)) }
            visualEffects.addAll(try self.visualEffects(clip, width: width, height: height, visual: visual))
            // CompositionPlayer needs source duration before clipping. Media
            // validation already reads this metadata for Transformer as well.
            let sourceDuration = mediaTiming[clip.getString("id")]?.duration ?? length
            let builder = EditedMediaItem.Builder(item).setDurationUs(sourceDuration).setRemoveAudio(true).setFrameRate(fps)
                .setEffects(Effects(java.util.ArrayList<AudioProcessor>(), visualEffects))
            if kind == "video" { builder.setSpeed(SpeedParameters(ConstantSpeedProvider(speed: Float(clip.getDouble("speed"))), true)) }
            let edited = builder.build()
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
            guard let timing = mediaTiming[clip.getString("id")], timing.hasAudio else { continue }
            let start = clip.getLong("startUs")
            let length = clip.getLong("durationUs")
            let sourceStart = clip.optLong("audioSourceStartUs", clip.getLong("sourceStartUs"))
            let audioURL = clip.optString("audioURL", clip.getString("url"))
            let audioTiming = kind == "audio" || audioURL == clip.getString("url") ? timing : try validateMedia(
                JSONObject(clip.toString()).put("url", audioURL).put("kind", "audio").put("sourceStartUs", sourceStart))
            let item = MediaItem.Builder().setUri(audioURL)
                .setClippingConfiguration(MediaItem.ClippingConfiguration.Builder().setStartPositionUs(sourceStart)
                    .setEndPositionUs(sourceStart + clip.getLong("sourceDurationUs")).build()).build()
            let processors = java.util.ArrayList<AudioProcessor>()
            if clip.optBoolean("customAudio", false) {
                processors.add(CustomAudioProcessor(id: clip.getString("id"), process: audio))
            } else if clip.getJSONArray("audioFilters").length() > 0 {
                processors.add(EqualizerAudioProcessor(filters: clip.getJSONArray("audioFilters")))
            }
            processors.add(EnvelopeAudioProcessor(clip: clip))
            let edited = EditedMediaItem.Builder(item).setDurationUs(audioTiming.duration).setRemoveVideo(true)
                .setSpeed(SpeedParameters(ConstantSpeedProvider(speed: Float(clip.getDouble("speed"))), true))
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

    /// Shared crop, filters, and fitting for encoded output and paused layer images.
    func visualEffects(_ clip: JSONObject, width: Int, height: Int,
                       visual: (String, Int) throws -> Media3VisualEffect = { _, _ in
                           throw IllegalArgumentException("Native visual effects require an export effect registry.")
                       }) throws -> java.util.ArrayList<Effect> {
        let visualEffects = java.util.ArrayList<Effect>()
        let transform = clip.getJSONObject("transform")
        let crop = transform.getJSONObject("crop")
        let filters = clip.getJSONArray("filters")
        for filterIndex in 0..<filters.length() {
            let filter = filters.getJSONObject(filterIndex)
            if filter.getString("kind") == "blur" {
                if filter.getDouble("value") > 0 { visualEffects.add(GaussianBlur(Float(filter.getDouble("value")))) }
            } else if filter.getString("kind") == "custom" {
                visualEffects.add(CustomShaderEffect(shader: filter.getJSONObject("shader"), clock: filter.getJSONObject("clock")))
            } else if filter.getString("kind") == "native" {
                visualEffects.add(try visual(clip.getString("id"), filterIndex).effect)
            } else { visualEffects.add(ColorMatrixEffect(kind: filter.getString("kind"), value: filter.getDouble("value"))) }
        }
        // Filters use source coordinates before crop and placement on both platforms.
        visualEffects.add(Crop(Float(crop.getDouble("x") * 2 - 1), Float((crop.getDouble("x") + crop.getDouble("width")) * 2 - 1),
                          Float(1 - (crop.getDouble("y") + crop.getDouble("height")) * 2), Float(1 - crop.getDouble("y") * 2)))
        let layout: Int
        switch transform.getString("contentMode") {
        case "fill": layout = Presentation.LAYOUT_SCALE_TO_FIT_WITH_CROP
        case "stretch": layout = Presentation.LAYOUT_STRETCH_TO_FIT
        default: layout = Presentation.LAYOUT_SCALE_TO_FIT
        }
        visualEffects.add(Presentation.createForWidthAndHeight(max(1, Int(Double(width) * transform.getDouble("width"))),
            max(1, Int(Double(height) * transform.getDouble("height"))), layout))
        return visualEffects
    }

    private struct MediaTiming {
        let duration: Int64
        let hasAudio: Bool
    }

    private func validateMedia(_ clip: JSONObject) throws -> MediaTiming {
        let extractor = MediaExtractor()
        defer { extractor.release() }
        // A prepared audio clip uses the cache's timeline, including any source
        // edit-list offset. Validate that exact file and its adjusted trim.
        let audio = clip.getString("kind") == "audio"
        let source = audio ? clip.optString("audioURL", clip.getString("url")) : clip.getString("url")
        let sourceStart = audio ? clip.optLong("audioSourceStartUs", clip.getLong("sourceStartUs")) : clip.getLong("sourceStartUs")
        extractor.setDataSource(ProcessInfo.processInfo.androidContext, Uri.parse(source), nil)
        var videoDuration: Int64 = -1
        var audioDuration: Int64 = -1
        for index in 0..<extractor.getTrackCount() {
            let format = extractor.getTrackFormat(index)
            let mime = format.getString(MediaFormat.KEY_MIME) ?? ""
            let duration = format.containsKey(MediaFormat.KEY_DURATION) ? format.getLong(MediaFormat.KEY_DURATION) : Int64(-1)
            if mime.hasPrefix("video/") { videoDuration = max(videoDuration, duration) }
            if mime.hasPrefix("audio/") {
                audioDuration = max(audioDuration, duration)
                EqualizerAudioProcessor.validate(clip.getJSONArray("audioFilters"), sampleRate: format.getInteger(MediaFormat.KEY_SAMPLE_RATE))
            }
        }
        let duration = audio ? audioDuration : videoDuration
        guard duration >= sourceStart + clip.getLong("sourceDurationUs") else {
            throw IllegalArgumentException("Missing media track or source range exceeds its duration: " + clip.getString("id"))
        }
        return MediaTiming(duration: max(videoDuration, audioDuration), hasAudio: audioDuration >= 0)
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
        let bitmap = try textImage(clip, width: width, height: height)
        return try saveBitmap(bitmap, name: clip.getString("id") + ".png", folder: folder)
    }

    func textImage(_ clip: JSONObject, width: Int, height: Int) throws -> Bitmap {
        let transform = clip.getJSONObject("transform")
        let textWidth = max(1, Int((Double(width) * transform.getDouble("width")).rounded()))
        let textHeight = max(1, Int((Double(height) * transform.getDouble("height")).rounded()))
        let bitmap = Bitmap.createBitmap(textWidth, textHeight, Bitmap.Config.ARGB_8888)
        let canvas = Canvas(bitmap)
        let style = clip.getJSONObject("textStyle")
        let paint = Media3TextRaster.paint(style)
        let alignment = Media3TextRaster.alignment(style)
        let text = clip.getString("text")
        let layout = StaticLayout.Builder.obtain(text, 0, text.length, paint, textWidth).setAlignment(alignment).setIncludePad(false).build()
        layout.draw(canvas)
        return bitmap
    }

    private func color(_ value: JSONObject) -> Int { Media3TextRaster.color(value) }

    private func saveBitmap(_ bitmap: Bitmap, name: String, folder: File) throws -> String {
        defer { bitmap.recycle() }
        return try Media3TextRaster.write(bitmap, name: name, folder: folder)
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
