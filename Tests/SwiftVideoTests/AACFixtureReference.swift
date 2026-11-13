// Copyright 2026 Software Deck Pty Ltd
// SPDX-License-Identifier: Apache-2.0

#if !SWIFTVIDEO_CORE_COVERAGE
/// Independent AVAssetReader measurements for the versioned AAC fixtures.
/// Kept shared so Android's cache is compared with the same timeline as Apple.
struct AACFixtureReference: Sendable {
    let name: String
    let offsetFrames: Int
    let middleRMS: Double
    static let initialRMS = 0.43126022232827604
    static let all = [
        AACFixtureReference(name: "music.m4a", offsetFrames: 0, middleRMS: 0.43177492425984365),
        AACFixtureReference(name: "red-with-music.mp4", offsetFrames: 0, middleRMS: 0.43177492425984365),
        AACFixtureReference(name: "red-with-offset-music.mp4", offsetFrames: 12_000, middleRMS: 0.43037719159152)
    ]
}
#endif
