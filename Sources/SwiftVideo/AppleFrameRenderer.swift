// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if canImport(AVFoundation)
import AVFoundation
import CoreImage
import CoreText
import QuartzCore

enum AppleFrameRenderer {
    static func compose(_ project: VideoProject, visualClips: [MediaClip], at time: VideoTime, size: VideoSize,
                        videos: [UUID: AppleVideoSource], images: [UUID: CIImage]) throws -> CIImage {
        let canvas = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        var frame = CIImage(color: project.background.ciColor).cropped(to: canvas)
        for clip in visualClips where try clip.timeRange.contains(time) {
            let source: CIImage
            if let video = videos[clip.id] {
                source = try video.image(at: time.subtracting(clip.start).adding(clip.sourceStart))
            } else if let image = images[clip.id] { source = image }
            else { throw VideoError.invalidMedia("No visual source was prepared for clip \(clip.id).") }
            let transform = try clip.visualTransform(at: time)
            let image = apply(clip.filters, to: source)
            let placed = place(image, transform: transform, canvas: canvas)
            frame = placed.composited(over: frame).cropped(to: canvas)
        }
        return frame
    }

    static func apply(_ filters: [MediaFilter], to source: CIImage) -> CIImage {
        filters.reduce(source) { image, filter in
            switch filter {
            case .brightness(let value): image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: value])
            case .contrast(let value): image.applyingFilter("CIColorControls", parameters: [kCIInputContrastKey: value])
            case .saturation(let value): image.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: value])
            case .sepia(let value): image.applyingFilter("CISepiaTone", parameters: [kCIInputIntensityKey: value])
            case .gaussianBlur(let value): image.clampedToExtent().applyingFilter("CIGaussianBlur", parameters: [kCIInputRadiusKey: value]).cropped(to: image.extent)
            }
        }
    }

    private static func place(_ source: CIImage, transform t: VisualTransform, canvas: CGRect) -> CIImage {
        let extent = source.extent
        let c = t.crop
        let crop = CGRect(x: extent.minX + extent.width * c.x, y: extent.minY + extent.height * (1 - c.y - c.height),
                          width: extent.width * c.width, height: extent.height * c.height)
        var image = source.cropped(to: crop).transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        let width = canvas.width * t.width
        let height = canvas.height * t.height
        var sx = width / crop.width
        var sy = height / crop.height
        switch t.contentMode {
        case .fit: sx = min(sx, sy); sy = sx
        case .fill: sx = max(sx, sy); sy = sx
        case .stretch: break
        }
        image = image.transformed(by: CGAffineTransform(scaleX: sx, y: sy))
            .transformed(by: CGAffineTransform(translationX: (width - crop.width * sx) / 2, y: (height - crop.height * sy) / 2))
            .cropped(to: CGRect(x: 0, y: 0, width: width, height: height))
        let matrix = CGAffineTransform(translationX: -width / 2, y: -height / 2)
            .concatenating(CGAffineTransform(scaleX: t.scale, y: t.scale))
            .concatenating(CGAffineTransform(rotationAngle: -t.rotation * .pi / 180))
            .concatenating(CGAffineTransform(translationX: canvas.width * t.x, y: canvas.height * (1 - t.y)))
        return image.transformed(by: matrix).applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: t.opacity)
        ])
    }

    /// Rasterize once at export resolution. Animation then stays in Core Image's render path.
    @MainActor
    static func textImage(_ text: String, style: TextStyle, project: VideoProject, size: VideoSize, rasterSize: VideoSize) throws -> CIImage {
        let scale = Double(size.width) / Double(project.canvas.width)
        let font: CTFont
        if let url = style.fontURL {
            guard let provider = CGDataProvider(url: url as CFURL), let cgFont = CGFont(provider) else {
                throw VideoError.invalidMedia("Cannot load custom font at \(url.lastPathComponent).")
            }
            font = CTFontCreateWithGraphicsFont(cgFont, style.fontSize * scale, nil, nil)
        } else {
            font = CTFontCreateWithName((style.fontName ?? "Helvetica") as CFString, style.fontSize * scale, nil)
            if let name = style.fontName, CTFontCopyPostScriptName(font) as String != name,
               CTFontCopyFamilyName(font) as String != name {
                throw VideoError.invalidMedia("Font \(name) is not available on this device. Supply a font file for portability.")
            }
        }
        let layer = CATextLayer()
        layer.frame = CGRect(x: 0, y: 0, width: rasterSize.width, height: rasterSize.height)
        layer.contentsScale = 1
        layer.font = font
        layer.fontSize = style.fontSize * scale
        layer.foregroundColor = style.color.cgColor
        layer.string = text
        layer.isWrapped = true
        switch style.alignment {
        case .leading: layer.alignmentMode = .left
        case .center: layer.alignmentMode = .center
        case .trailing: layer.alignmentMode = .right
        }
        if let shadow = style.shadow {
            layer.shadowColor = shadow.color.cgColor
            layer.shadowOpacity = Float(shadow.color.alpha)
            layer.shadowRadius = shadow.radius * scale
            layer.shadowOffset = CGSize(width: shadow.x * scale, height: shadow.y * scale)
        }
        guard let context = CGContext(data: nil, width: rasterSize.width, height: rasterSize.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw VideoError.renderingFailed("Cannot allocate text bitmap.")
        }
        #if canImport(UIKit)
        // UIKit's layer text uses a top-left origin; Core Image consumes an upright bitmap.
        context.translateBy(x: 0, y: CGFloat(rasterSize.height))
        context.scaleBy(x: 1, y: -1)
        #endif
        layer.render(in: context)
        guard let image = context.makeImage() else { throw VideoError.renderingFailed("Cannot render text bitmap.") }
        return CIImage(cgImage: image)
    }
}

extension VideoColor {
    var ciColor: CIColor { CIColor(red: red, green: green, blue: blue, alpha: alpha) }
    var cgColor: CGColor { CGColor(red: red, green: green, blue: blue, alpha: alpha) }
}
#endif
