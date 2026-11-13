// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if SKIP
import Foundation
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.net.Uri
import android.text.Layout
import android.text.SpannableString
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.style.CharacterStyle
import java.io.File
import java.io.FileOutputStream
import org.json.JSONObject

struct MotionTitlePiece { let index: Int; let bounds: Rect; let atlas: Rect }

final class MotionTitleRaster {
    let id: String, path: String
    let width: Int, height: Int, atlasWidth: Int, atlasHeight: Int, unitCount: Int
    let pieces: [MotionTitlePiece]
    init(id: String, path: String, width: Int, height: Int, atlasWidth: Int, atlasHeight: Int,
         unitCount: Int, pieces: [MotionTitlePiece]) {
        self.id = id; self.path = path; self.width = width; self.height = height
        self.atlasWidth = atlasWidth; self.atlasHeight = atlasHeight; self.unitCount = unitCount; self.pieces = pieces
    }
}

/// Layout and rasterization happen once. The GL effect reuses this packed glyph atlas.
final class Media3TextRaster {
    static func paint(_ style: JSONObject, shadow: Bool = true) -> TextPaint {
        let paint = TextPaint(android.graphics.Paint.ANTI_ALIAS_FLAG)
        paint.setTextSize(Float(style.getDouble("fontSize")))
        paint.setColor(color(style.getJSONObject("color")))
        if style.has("fontURL") {
            paint.setTypeface(Typeface.createFromFile(Uri.parse(style.getString("fontURL")).getPath()))
        } else if style.has("fontName") {
            paint.setTypeface(Typeface.create(style.getString("fontName"), Typeface.NORMAL))
        } else { paint.setTypeface(Typeface.DEFAULT) }
        if shadow { applyShadow(style, to: paint) }
        return paint
    }

    static func applyShadow(_ style: JSONObject, to paint: TextPaint) {
        if style.has("shadow") {
            let shadow = style.getJSONObject("shadow")
            paint.setShadowLayer(Float(shadow.getDouble("radius")), Float(shadow.getDouble("x")),
                Float(shadow.getDouble("y")), color(shadow.getJSONObject("color")))
        }
    }

    static func alignment(_ style: JSONObject) -> Layout.Alignment {
        switch style.getString("alignment") {
        case "leading": return Layout.Alignment.ALIGN_NORMAL
        case "trailing": return Layout.Alignment.ALIGN_OPPOSITE
        default: return Layout.Alignment.ALIGN_CENTER
        }
    }

    static func color(_ value: JSONObject) -> Int {
        Color.argb(Int(value.getDouble("alpha") * 255), Int(value.getDouble("red") * 255),
            Int(value.getDouble("green") * 255), Int(value.getDouble("blue") * 255))
    }

    /// The caller owns the bitmap; this helper owns only the output stream.
    static func write(_ bitmap: Bitmap, name: String, folder: File) throws -> String {
        let file = File(folder, name)
        let stream = FileOutputStream(file)
        defer { stream.close() }
        guard bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream) else { throw IllegalStateException("Cannot encode overlay image.") }
        return Uri.fromFile(file).toString()
    }

    static func motion(_ clip: JSONObject, width: Int, height: Int, folder: File) throws -> MotionTitleRaster {
        let transform = clip.getJSONObject("transform"), style = clip.getJSONObject("textStyle")
        let textWidth = max(1, Int((Double(width) * transform.getDouble("width")).rounded()))
        let textHeight = max(1, Int((Double(height) * transform.getDouble("height")).rounded()))
        let motion = clip.getJSONObject("textMotion"), ranges = motion.getJSONArray("ranges")
        let text = clip.getString("text")
        let spans = SpannableString(text)
        let paint = paint(style, shadow: false)
        paint.setColor(Color.TRANSPARENT)
        if motion.getString("unit") == "character" { paint.setFontFeatureSettings("'liga' 0") }
        let layout = StaticLayout.Builder.obtain(spans, 0, text.length, paint, textWidth)
            .setAlignment(alignment(style)).setIncludePad(false).build()
        var padding = style.getDouble("fontSize") / 2 + 2
        if style.has("shadow") {
            let shadow = style.getJSONObject("shadow")
            padding += shadow.getDouble("radius") * 3 + max(abs(shadow.getDouble("x")), abs(shadow.getDouble("y")))
        }
        var records: [MotionTitlePiece] = []
        var pixels = 0, maxWidth = 1
        for index in 0..<ranges.length() {
            let range = ranges.getJSONObject(index)
            let path = Path(), bounds = RectF(), rounded = Rect()
            layout.getSelectionPath(range.getInt("start"), range.getInt("start") + range.getInt("length"), path)
            path.computeBounds(bounds, true)
            if bounds.isEmpty() { continue }
            bounds.inset(-Float(padding), -Float(padding))
            if !bounds.intersect(Float(0), Float(0), Float(textWidth), Float(textHeight)) { continue }
            bounds.roundOut(rounded)
            pixels += rounded.width() * rounded.height()
            guard rounded.width() <= 4096, rounded.height() <= 4096, pixels <= 16_777_216 else {
                throw IllegalArgumentException("Motion title rasters exceed the 4096-pixel atlas or 64 MiB preparation budget.")
            }
            maxWidth = max(maxWidth, rounded.width())
            records.append(MotionTitlePiece(index: index, bounds: rounded, atlas: Rect()))
        }
        let preferredWidth = Int(ceil(sqrt(Double(max(1, pixels)))))
        let atlasWidth = min(4096, max(maxWidth, preferredWidth))
        var x = 0, y = 0, rowHeight = 0
        var pieces: [MotionTitlePiece] = []
        for record in records {
            let width = record.bounds.width(), height = record.bounds.height()
            if x + width > atlasWidth { x = 0; y += rowHeight; rowHeight = 0 }
            guard y + height <= 4096 else { throw IllegalArgumentException("Motion title atlas exceeds 4096 pixels in height.") }
            pieces.append(MotionTitlePiece(index: record.index, bounds: record.bounds, atlas: Rect(x, y, x + width, y + height)))
            x += width; rowHeight = max(rowHeight, height)
        }
        let atlasHeight = max(1, y + rowHeight)
        let bitmap = Bitmap.createBitmap(atlasWidth, atlasHeight, Bitmap.Config.ARGB_8888)
        defer { bitmap.recycle() }
        let canvas = Canvas(bitmap), span = MotionTitleSpan(style: style)
        for piece in pieces {
            let range = ranges.getJSONObject(piece.index)
            spans.setSpan(span, range.getInt("start"), range.getInt("start") + range.getInt("length"), Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
            let saved = canvas.save()
            canvas.clipRect(piece.atlas)
            canvas.translate(Float(piece.atlas.left - piece.bounds.left), Float(piece.atlas.top - piece.bounds.top))
            layout.draw(canvas)
            canvas.restoreToCount(saved)
            spans.removeSpan(span)
        }
        let path = try write(bitmap, name: clip.getString("id") + "-atlas.png", folder: folder)
        return MotionTitleRaster(id: clip.getString("id"), path: path, width: textWidth, height: textHeight,
            atlasWidth: atlasWidth, atlasHeight: atlasHeight, unitCount: ranges.length(), pieces: pieces)
    }
}

/// Draw-only spans keep one measured layout while hiding every other unit, including its shadow.
private final class MotionTitleSpan: CharacterStyle {
    let style: JSONObject
    init(style: JSONObject) { self.style = style; super.init() }
    override func updateDrawState(tp: TextPaint) {
        tp.setColor(Media3TextRaster.color(style.getJSONObject("color")))
        Media3TextRaster.applyShadow(style, to: tp)
    }
}
#endif
