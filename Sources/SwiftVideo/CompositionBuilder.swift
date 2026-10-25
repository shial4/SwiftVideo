// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

/// A value builder for tracks and clips. Supports conditionals, loops, and reusable arrays.
/// Building a project does not load media, render frames, or require the main actor.
@resultBuilder public enum VideoBuilder<Element: Sendable> {
    public static func buildExpression(_ element: Element) -> [Element] { [element] }
    public static func buildExpression(_ elements: [Element]) -> [Element] { elements }
    public static func buildBlock(_ components: [Element]...) -> [Element] { components.flatMap { $0 } }
    public static func buildOptional(_ component: [Element]?) -> [Element] { component ?? [] }
    public static func buildEither(first: [Element]) -> [Element] { first }
    public static func buildEither(second: [Element]) -> [Element] { second }
    public static func buildArray(_ components: [[Element]]) -> [Element] { components.flatMap { $0 } }
    public static func buildLimitedAvailability(_ component: [Element]) -> [Element] { component }
}

extension VideoProject {
    public init(canvas: VideoSize = .hd1080, frameRate: FrameRate = .fps30, background: VideoColor = .black,
                @VideoBuilder<MediaTrack> tracks: () throws -> [MediaTrack]) rethrows {
        self.init(canvas: canvas, frameRate: frameRate, background: background, tracks: try tracks())
    }
}

extension MediaTrack {
    public init(_ name: String = "", id: UUID = UUID(), @VideoBuilder<MediaClip> clips: () throws -> [MediaClip]) rethrows {
        self.init(id: id, name: name, clips: try clips())
    }
}

extension MediaClip {
    public static func video(_ url: URL, duration: VideoTime, id: UUID = UUID()) -> MediaClip {
        MediaClip(id: id, source: .video(url), duration: duration)
    }
    public static func image(_ url: URL, duration: VideoTime, id: UUID = UUID()) -> MediaClip {
        MediaClip(id: id, source: .image(url), duration: duration)
    }
    public static func text(_ value: String, duration: VideoTime, style: TextStyle = TextStyle(), id: UUID = UUID()) -> MediaClip {
        MediaClip(id: id, source: .text(value, style), duration: duration)
    }
    public static func audio(_ url: URL, duration: VideoTime, id: UUID = UUID()) -> MediaClip {
        MediaClip(id: id, source: .audio(url), duration: duration)
    }

    /// Modifiers return new values and preserve the clip ID and original effect clock.
    public func starting(at time: VideoTime) -> MediaClip { replacing(start: time) }
    public func sourceStarting(at time: VideoTime) -> MediaClip { replacing(sourceStart: time) }
    public func source(_ source: MediaSource) -> MediaClip { replacing(source: source) }
    public func zIndex(_ index: Int) -> MediaClip { replacing(zIndex: index) }
    public func transform(_ transform: VisualTransform) -> MediaClip { replacing(transform: transform) }
    public func filters(_ filters: [MediaFilter]) -> MediaClip { replacing(filters: filters) }
    public func filter(_ filter: MediaFilter) -> MediaClip { replacing(filters: filters + [filter]) }
    public func audio(_ settings: AudioSettings) -> MediaClip { replacing(audio: settings) }
    public func animations(_ animations: [KeyframeAnimation]) -> MediaClip { replacing(animations: animations) }
    public func animate(_ property: AnimationProperty, keyframes: [Keyframe]) -> MediaClip {
        // One owner per animated property, matching project validation.
        replacing(animations: animations.filter { $0.property != property } + [KeyframeAnimation(property: property, keyframes: keyframes)])
    }

    func textRasterSize(for output: VideoSize) throws -> VideoSize {
        let width = Double(output.width) * transform.width
        let height = Double(output.height) * transform.height
        guard width.isFinite, height.isFinite, width > 0, height > 0, width <= 8192, height <= 8192 else {
            throw VideoError.unsupportedFeature("Text layer bounds must fit within an 8192-pixel bitmap.")
        }
        return VideoSize(width: max(1, Int(width.rounded())), height: max(1, Int(height.rounded())))
    }
}
