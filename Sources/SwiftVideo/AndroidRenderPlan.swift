// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A private wire format for the Skip service boundary, separate from the public project format.
/// All validation and timeline rules remain in the native Swift module.
struct AndroidRenderPlan: Encodable {
    let width: Int
    let height: Int
    let frameRate: Double
    let durationUs: Int64
    let videoBitRate: Int
    let audioBitRate: Int
    let codec: String
    let background: VideoColor
    let clips: [Clip]

    struct Clip: Encodable {
        let id: String
        let kind: String
        let url: String
        let text: String
        let textStyle: TextStyle?
        let textMotion: TitleMotion?
        let startUs: Int64
        let durationUs: Int64
        let sourceStartUs: Int64
        let sourceDurationUs: Int64
        let speed: Double
        let audioFilters: [AudioEffect]
        let customAudio: Bool
        let transform: VisualTransform
        let filters: [Filter]
        let muted: Bool
        let leftGain: Double
        let rightGain: Double
        let envelope: [GainPoint]
    }
    struct AudioEffect: Encodable { let kind: String; let frequencyHz: Double; let gainDB: Double; let bandwidthOctaves: Double }
    struct TitleMotion: Encodable { let unit: TextMotionUnit; let ranges: [TextMotion.Range] }
    struct Filter: Encodable {
        let kind: String
        let value: Double
        let shader: AndroidVisualEffect?
        let clock: EffectClock?
        init(kind: String, value: Double = 0, shader: AndroidVisualEffect? = nil, clock: EffectClock? = nil) {
            self.kind = kind; self.value = value; self.shader = shader; self.clock = clock
        }
    }
    struct GainPoint: Encodable { let seconds: Double; let gain: Double }

    init(project: VideoProject, settings: ExportSettings, effects: EffectRegistry = .empty) throws {
        let size = settings.resolution ?? project.canvas
        width = size.width; height = size.height
        frameRate = (settings.frameRate ?? project.frameRate).framesPerSecond
        durationUs = try Self.microseconds(project.duration)
        videoBitRate = try settings.effectiveVideoBitRate(for: project)
        audioBitRate = settings.audioBitRate
        codec = settings.codec.rawValue
        background = project.background
        // Media3 draws earlier sequences above later sequences.
        let ordered = try project.renderClips().enumerated().sorted {
            $0.element.zIndex == $1.element.zIndex ? $0.offset > $1.offset : $0.element.zIndex > $1.element.zIndex
        }.map(\.element)
        clips = try ordered.map { clip in
            let kind: String
            var text = ""
            var style: TextStyle?
            switch clip.source {
            case .video: kind = "video"
            case .audio: kind = "audio"
            case .image: kind = "image"
            case .text(let value, let original):
                _ = try clip.textRasterSize(for: size)
                kind = "text"; text = value
                let scale = Double(size.width) / Double(project.canvas.width)
                let shadow = original.shadow.map {
                    TextShadow(color: $0.color, radius: $0.radius * scale, x: $0.x * scale, y: $0.y * scale)
                }
                style = TextStyle(fontName: original.fontName, fontURL: original.fontURL,
                                  fontSize: original.fontSize * scale,
                                  color: original.color, alignment: original.alignment, shadow: shadow)
            }
            let filters = try clip.filters.map { filter -> Filter in
                switch filter {
                case .brightness(let value): return Filter(kind: "brightness", value: value)
                case .contrast(let value): return Filter(kind: "contrast", value: value)
                case .saturation(let value): return Filter(kind: "saturation", value: value)
                case .sepia(let value): return Filter(kind: "sepia", value: value)
                case .gaussianBlur(let value): return Filter(kind: "blur", value: value)
                case .custom(let reference):
                    let (definition, parameters) = try effects.resolve(reference, for: .android)
                    guard let factory = definition.androidFactory else {
                        throw VideoError.unsupportedFeature("The custom effect has no Android implementation.")
                    }
                    let shader = try factory(parameters)
                    try shader.validate()
                    return Filter(kind: "custom", shader: shader, clock: EffectClock(clip: clip))
                }
            }
            let audioFilters = clip.audio.filters.compactMap { filter -> AudioEffect? in
                switch filter {
                case .custom: nil
                case .lowPass(let cutoff): AudioEffect(kind: "lowPass", frequencyHz: cutoff, gainDB: 0, bandwidthOctaves: 1)
                case .highPass(let cutoff): AudioEffect(kind: "highPass", frequencyHz: cutoff, gainDB: 0, bandwidthOctaves: 1)
                case .parametricEQ(let frequency, let gain, let bandwidth):
                    AudioEffect(kind: "parametricEQ", frequencyHz: frequency, gainDB: gain, bandwidthOctaves: bandwidth)
                }
            }
            let start = clip.effectsOffset.seconds
            let end = start + clip.duration.seconds
            let breakpoints = Set([start, end, max(start, min(end, clip.audio.fadeIn.seconds)),
                                   max(start, min(end, clip.effectsDuration.seconds - clip.audio.fadeOut.seconds))]).sorted()
            let envelope = breakpoints.map { time in
                GainPoint(seconds: time - start, gain: clip.audio.gain(atSeconds: time, durationSeconds: clip.effectsDuration.seconds, includeEnd: true))
            }
            let textMotion = clip.textMotion.map { TitleMotion(unit: $0.unit, ranges: $0.ranges(in: text)) }
            return Clip(id: clip.id.uuidString, kind: kind, url: clip.source.url?.absoluteString ?? "", text: text, textStyle: style, textMotion: textMotion,
                        startUs: try Self.microseconds(clip.start), durationUs: try Self.microseconds(clip.duration),
                        sourceStartUs: try Self.microseconds(clip.sourceStart),
                        sourceDurationUs: try Self.microseconds(clip.sourceDuration), speed: clip.playbackRate.multiplier,
                        audioFilters: audioFilters, customAudio: clip.audio.filters.contains(where: \.isCustom), transform: clip.transform, filters: filters,
                        muted: clip.audio.isMuted || !clip.source.hasAudio,
                        leftGain: sqrt(1 - clip.audio.pan), rightGain: sqrt(1 + clip.audio.pan), envelope: envelope)
        }
    }

    private static func microseconds(_ time: VideoTime) throws -> Int64 {
        guard time >= .zero else { throw VideoError.timeOverflow }
        let product = UInt64(time.value).multipliedFullWidth(by: 1_000_000)
        let divisor = UInt64(time.timescale)
        guard product.high < divisor else { throw VideoError.timeOverflow }
        let result = divisor.dividingFullWidth(product)
        let rounded = result.quotient.addingReportingOverflow(result.remainder * 2 >= divisor ? 1 : 0)
        guard !rounded.overflow, rounded.partialValue <= UInt64(Int64.max) else { throw VideoError.timeOverflow }
        return Int64(rounded.partialValue)
    }
}
