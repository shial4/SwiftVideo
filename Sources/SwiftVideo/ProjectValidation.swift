// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

import Foundation

extension VideoProject {
    /// Validates serialized or programmatically built input before editing or rendering.
    /// Asset readability and backend-specific limits are checked separately by the renderer.
    public func validate() throws {
        try require(canvas.width > 0 && canvas.height > 0, "Canvas dimensions must be positive.")
        try validateColor(background)
        var trackIDs: Set<UUID> = []
        var clipIDs: Set<UUID> = []
        for track in tracks {
            try require(trackIDs.insert(track.id).inserted, "Track IDs must be unique.")
            for clip in track.clips {
                try require(clipIDs.insert(clip.id).inserted, "Clip IDs must be unique across the project.")
                try validateClip(clip)
            }
        }
        _ = try duration
    }
}

private func require(_ condition: Bool, _ message: String) throws {
    guard condition else { throw VideoError.invalidProject(message) }
}

private func validateColor(_ color: VideoColor) throws {
    try require([color.red, color.green, color.blue, color.alpha].allSatisfy { $0.isFinite && (0...1).contains($0) },
                "Color components must be finite and between zero and one.")
}

private func validateClip(_ clip: MediaClip) throws {
    try require(clip.start >= .zero && clip.sourceStart >= .zero && clip.duration > .zero,
                "Clip start and source start must be nonnegative; duration must be positive.")
    _ = try clip.sourceStart.adding(clip.duration)
    try require(clip.effectsOffset >= .zero && clip.effectsDuration > .zero,
                "Effect timing must have a nonnegative offset and positive duration.")
    try require(try clip.effectsOffset.adding(clip.duration) <= clip.effectsDuration,
                "The clip must fit within its original effect duration.")
    if let url = clip.source.url {
        try require(url.isFileURL || ["https", "http", "content"].contains(url.scheme?.lowercased() ?? ""),
                    "Media requires a file, HTTP(S), or Android content URL.")
    }
    if case .text(let text, let style) = clip.source {
        try require(!text.isEmpty, "Text overlays cannot be empty.")
        try require(style.fontSize.isFinite && style.fontSize > 0, "Font size must be finite and positive.")
        try validateColor(style.color)
        if let font = style.fontURL { try require(font.isFileURL, "Custom fonts require a local file URL.") }
        if let shadow = style.shadow {
            try validateColor(shadow.color)
            try require([shadow.radius, shadow.x, shadow.y].allSatisfy(\.isFinite) && shadow.radius >= 0,
                        "Text shadow values must be finite and radius nonnegative.")
        }
    }
    let t = clip.transform
    try require([t.x, t.y, t.width, t.height, t.scale, t.rotation, t.opacity].allSatisfy(\.isFinite),
                "Transforms must contain finite values.")
    try require(t.width > 0 && t.height > 0 && t.scale > 0 && (0...1).contains(t.opacity),
                "Transform dimensions and scale must be positive, and opacity between zero and one.")
    let c = t.crop
    try require([c.x, c.y, c.width, c.height].allSatisfy(\.isFinite) && c.x >= 0 && c.y >= 0 && c.width > 0
                && c.height > 0 && c.x + c.width <= 1 && c.y + c.height <= 1, "Crop must fit within the source image.")
    for filter in clip.filters {
        switch filter {
        case .brightness(let value): try require(value.isFinite && (-1...1).contains(value), "Brightness must be between -1 and 1.")
        case .contrast(let value), .saturation(let value): try require(value.isFinite && value >= 0, "Contrast and saturation must be nonnegative.")
        case .gaussianBlur(let value): try require(value.isFinite && value >= 0, "Blur radius must be nonnegative.")
        case .sepia(let value): try require(value.isFinite && (0...1).contains(value), "Sepia intensity must be between zero and one.")
        }
    }
    var properties: Set<AnimationProperty> = []
    for animation in clip.animations {
        try require(properties.insert(animation.property).inserted, "Only one animation per property is allowed on a clip.")
        try require(!animation.keyframes.isEmpty, "Animations require at least one keyframe.")
        var previous: VideoTime?
        for keyframe in animation.keyframes {
            try require(keyframe.time >= .zero && keyframe.time <= clip.effectsDuration && keyframe.value.isFinite,
                        "Keyframes require a finite value and a time inside the original effect duration.")
            if let previous { try require(keyframe.time > previous, "Keyframe times must be strictly increasing.") }
            if animation.property == .opacity { try require((0...1).contains(keyframe.value), "Animated opacity must be between zero and one.") }
            if animation.property == .scale { try require(keyframe.value > 0, "Animated scale must be positive.") }
            previous = keyframe.time
        }
    }
    let a = clip.audio
    try require(a.volume.isFinite && a.volume >= 0 && a.pan.isFinite && (-1...1).contains(a.pan), "Invalid audio gain or pan.")
    try require(a.fadeIn >= .zero && a.fadeOut >= .zero, "Audio fades must be nonnegative.")
    try require(try a.fadeIn.adding(a.fadeOut) <= clip.effectsDuration, "Audio fades must fit within the original clip duration.")
}
