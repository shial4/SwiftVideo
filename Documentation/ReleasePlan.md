<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo release plan

[Documentation index](README.md) | [Tests and coverage](Testing.md)

Reviewed November 22, 2026. Release 0.0.2 promotes the stable implementation from `0.0.2-beta.4`. Preview and extensibility remain on `develop`; [PR #6](https://github.com/shial4/SwiftVideo/pull/6) stays unmerged.

## Release scope

| Release line | Contents | Dependency policy |
| --- | --- | --- |
| `0.0.2` | Composition/export, clip and track speed, inherited visual filters, ordered audio EQ, and reliability fixes | Stable Media3 1.11.1 |
| `0.1.0-alpha.*` and `develop` | Experimental composition/layer preview, custom effects, motion titles, animation extensions, masks and optional segmentation | Prerelease dependencies remain experimental; require compatible stable dependencies before merging into `main` |

The stable release preserves beta.4's library implementation, tests, dependency pins, example and test tooling. Android CI runs the example build separately and reuses the cached setup from `develop`; test assertions, coverage gates and runtime limits are unchanged. Release documentation and CI changes do not add preview or extensibility APIs. Existing beta and alpha tags are immutable, including [0.0.2-beta.4](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.4) and [0.1.0-alpha.7](https://github.com/shial4/SwiftVideo/releases/tag/0.1.0-alpha.7).

## Maintainer acceptance

On November 21, the maintainer requested the stable 0.0.2 release and reported using beta.4 in Swideo without noticing problems. This is maintainer-reported application acceptance. Exact usage dates were not supplied, so this record does not claim that the previously proposed five-working-day observation window was independently verified. The promotion uses that acceptance together with the automated and independent-consumer evidence below.

The maintainer's earlier decision, "Ship with color limitation", accepts the measured bounded SDR color-conversion difference for 0.0.2. Keep the [measurements and scope](Testing.md#known-color-limitation) visible. This exception does not waive audio, timing, missing frames, alpha/opacity, filter, cancellation or cleanup regressions, and it does not establish a general color-fidelity guarantee.

## Verification and publication

Beta.4 is frozen at `311107384330d3c1670546b6eeef806447fdb0d9`. Its [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42682862180) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42682863148) passed, including both example builds and all coverage gates. Independent SwiftPM and Kotlin/AAR consumers resolved the exact tag and passed exports, fractional PCM trims and failure cleanup.

The first promotion run at `c7796a1` passed [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/44897275670). [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/44897275687) reached its 45-minute build-job limit while assembling the example APK, after native compilation and test packaging passed. The dependent runtime job was skipped. On November 22, the maintainer approved separating the example build and reusing the cached setup from `develop`. The release still requires all jobs to pass on its exact commit.

Final promotion follows these steps:

1. Verify that the stable implementation and dependency graph still match beta.4. Keep experimental source on `develop`.
2. Run the stable macOS and editor suites and refresh independent iOS Simulator and Android API 35 consumer checks. Verify the title/image and captioned picture-in-picture scene, audio timing, dimensions and decoded output.
3. Update installation and API-availability documentation for 0.0.2. Record maintainer acceptance separately from measured test results.
4. Push the stable promotion to `main` and require both platform workflows at that exact commit, including all tests, example builds and coverage gates.
5. Tag that passing release commit as `0.0.2`, publish the tag with its release, and check package consumers against the published tag. Do not move an existing tag or tag unreleased work.

The release's exact commit and final CI links are recorded in the [0.0.2 release notes](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2). [Testing documentation](Testing.md) distinguishes historical beta evidence, local promotion checks and hosted verification.

## Required gates

| Area | Requirement |
| --- | --- |
| Apple | All applicable macOS/iOS tests, editor model tests and example build pass |
| Android | Native Swift core tests, real Media3 app tests and example build pass on hosted API 34; targeted API 35 consumer checks pass |
| Coverage | At least 90% iOS source lines, 90% Android shared Swift core lines and 75% Media3 bridge bytecode lines, using the existing separate scopes |
| Behavior | Correct speed, pitch, source ranges, filter order, decoded overlays/audio, duration, cancellation, cleanup and destination protection |
| Compatibility | Existing project JSON decodes; independent SwiftPM and Kotlin wrapper consumers resolve the intended release and export successfully |
| Dependencies | Published stable dependencies; no local dependency patches or unpublished native helpers |
| Documentation | Installation version, API availability, verification dates/scopes and limitations agree with the release |

Use existing toolchains. Routine render fixtures stay at 320x180; the separate delivery-resolution smoke export uses 1280x720. Preserve all behavioral assertions and coverage thresholds. Do not retry until green or relax checks to conceal failures. A new media-behavior defect requires a fix and a new verified candidate.

Simulator and emulator verification is the agreed release scope. Physical-device access is not a prerequisite. Hardware codecs, vendor GPU/driver behavior, thermal limits and sustained phone performance remain unverified.

## Earlier candidate fixes

| Superseded beta | Finding | Corrected in |
| --- | --- | --- |
| `0.0.2-beta.1` | Cancellation could close a video track before its first sample and crash the duration-configured Android muxer | beta.2 guards the timeline marker while retaining one-frame duration |
| `0.0.2-beta.2` | Apple offline audio graph initialization could initialize RemoteIO before offline mode | beta.3 enables offline mode before graph construction |
| `0.0.2-beta.3` | Fractional PCM trims could add silence and shift fades on Android | beta.4 normalizes selected PCM samples before export |

Those fixes remain covered by beta.4's unchanged tests. Their bounded CPU audio preparation does not alter GPU visual composition. Earlier tags are preserved for reproducibility and are not promoted.

## Development after 0.0.2

Keep one active development branch, `develop`, and [PR #6](https://github.com/shial4/SwiftVideo/pull/6). Superseded PRs #1, #4 and #5 are closed. Do not merge the preview/effects branch as part of this stable release.

The development implementation still uses Media3 1.12.0-alpha02. Its Apple CI passes; Android compilation and core tests pass, but raw seek and color diagnostics still fail and the hosted Android coverage gate is skipped. The November 13 beta01 candidate check did not clear those failures. Preview needs compatible stable dependencies and passing runtime/coverage gates before merging. Current development evidence and upstream monitoring belong in the [develop release plan](https://github.com/shial4/SwiftVideo/blob/develop/Documentation/ReleasePlan.md) and [PR #6](https://github.com/shial4/SwiftVideo/pull/6).
