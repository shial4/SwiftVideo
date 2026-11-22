// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import CoreImage
import CoreText
import Foundation

/// Core Text shapes once. Each unit's raster is reused by the GPU throughout export.
/// Font shaping and glyph runs stay on the owning renderer's serial executor.
final class AppleMotionTitle {
    private struct DrawRun { let run: CTRun; let range: CFRange; let origin: CGPoint }
    private struct Unit { let index: Int; let image: CIImage; let bounds: CGRect }
    private let clip: MediaClip
    private let motion: TextMotion
    private let canvas: CGRect
    private let units: [Unit]

    init(text: String, style: TextStyle, clip: MediaClip, project: VideoProject, size: VideoSize) throws {
        guard let motion = clip.textMotion else { throw VideoError.invalidProject("A motion title requires text motion.") }
        self.clip = clip; self.motion = motion
        let raster = try clip.textRasterSize(for: size)
        canvas = CGRect(x: 0, y: 0, width: raster.width, height: raster.height)
        let scale = Double(size.width) / Double(project.canvas.width)
        let font = try AppleFrameRenderer.makeFont(style, size: style.fontSize * scale)
        var alignment: CTTextAlignment
        switch style.alignment {
        case .leading: alignment = .left
        case .center: alignment = .center
        case .trailing: alignment = .right
        }
        let paragraph = withUnsafePointer(to: &alignment) { pointer in
            var setting = CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)
            return CTParagraphStyleCreate(&setting, 1)
        }
        let attributed = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): style.color.cgColor,
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): paragraph,
            NSAttributedString.Key(kCTLigatureAttributeName as String): motion.unit == .character ? 0 : 1
        ])
        let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed), CFRange(),
            CGPath(rect: canvas, transform: nil), nil)
        let lines = CTFrameGetLines(frame) as! [CTLine]
        var origins = [CGPoint](repeating: .zero, count: lines.count)
        CTFrameGetLineOrigins(frame, CFRange(), &origins)
        let ranges = motion.ranges(in: text)
        var draws = [[DrawRun]](repeating: [], count: ranges.count)
        var bounds = [CGRect](repeating: .null, count: ranges.count)
        for (lineIndex, line) in lines.enumerated() {
            for run in CTLineGetGlyphRuns(line) as! [CTRun] {
                let count = CTRunGetGlyphCount(run)
                var indices = [CFIndex](repeating: 0, count: count)
                CTRunGetStringIndices(run, CFRange(), &indices)
                var cursor = 0
                while cursor < count {
                    guard let index = ranges.firstIndex(where: { indices[cursor] >= $0.start && indices[cursor] < $0.start + $0.length }) else {
                        cursor += 1; continue
                    }
                    let start = cursor
                    while cursor < count, indices[cursor] >= ranges[index].start,
                          indices[cursor] < ranges[index].start + ranges[index].length { cursor += 1 }
                    let range = CFRange(location: start, length: cursor - start)
                    let origin = origins[lineIndex]
                    draws[index].append(DrawRun(run: run, range: range, origin: origin))
                    let ink = CTRunGetImageBounds(run, nil, range).offsetBy(dx: origin.x, dy: origin.y)
                    if !ink.isNull { bounds[index] = bounds[index].union(ink) }
                }
            }
        }
        var prepared: [Unit] = []
        var pixels = 0
        for index in ranges.indices where !bounds[index].isNull {
            try Task.checkCancellation()
            let padding = style.shadow.map { ($0.radius * 3 + max(abs($0.x), abs($0.y))) * scale + 2 } ?? 2
            let rect = bounds[index].insetBy(dx: -padding, dy: -padding).integral.intersection(canvas)
            guard !rect.isEmpty else { continue }
            let width = Int(rect.width), height = Int(rect.height)
            pixels += width * height
            guard pixels <= 16_777_216 else { throw VideoError.unsupportedFeature("Motion title rasters exceed the 64 MiB preparation budget.") }
            guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
                throw VideoError.renderingFailed("Cannot allocate motion-title glyph bitmap.")
            }
            context.translateBy(x: -rect.minX, y: -rect.minY)
            if let shadow = style.shadow {
                context.setShadow(offset: CGSize(width: shadow.x * scale, height: -shadow.y * scale),
                    blur: shadow.radius * scale, color: shadow.color.cgColor)
            }
            for draw in draws[index] {
                context.textMatrix = .identity
                context.textPosition = draw.origin
                CTRunDraw(draw.run, context, draw.range)
            }
            guard let image = context.makeImage() else { throw VideoError.renderingFailed("Cannot rasterize motion-title glyphs.") }
            prepared.append(Unit(index: index, image: CIImage(cgImage: image), bounds: rect))
        }
        units = prepared
    }

    func image(at time: VideoTime) throws -> CIImage {
        let local = try time.subtracting(clip.start).adding(clip.effectsOffset)
        var result = CIImage(color: .clear).cropped(to: canvas)
        for unit in units {
            let t = try motion.transform(forUnit: unit.index, at: local)
            if t.opacity <= 0 { continue }
            let matrix = CGAffineTransform(translationX: -unit.bounds.width / 2, y: -unit.bounds.height / 2)
                .concatenating(CGAffineTransform(scaleX: t.scale, y: t.scale))
                .concatenating(CGAffineTransform(rotationAngle: -t.rotation * .pi / 180))
                .concatenating(CGAffineTransform(translationX: unit.bounds.midX + t.x * canvas.width,
                                                y: unit.bounds.midY - t.y * canvas.height))
            let placed = unit.image.transformed(by: matrix).applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: t.opacity)
            ])
            result = placed.composited(over: result)
        }
        return result.cropped(to: canvas)
    }
}
#endif
