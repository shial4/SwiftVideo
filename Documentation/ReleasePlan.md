<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo release plan

[Documentation index](README.md) | [Tests and coverage](Testing.md)

Reviewed November 22, 2026. Stable **0.0.2 is published** at `af717712951834e18d2d1266c4102fc0503743f6`. Release evidence below retains its original dates. Continue all unreleased preview and extensibility work on `develop` in one draft PR to `main`. This scope supersedes the earlier proposal to include extensibility in 0.0.2.

At the maintainer's request, release verification uses the iOS Simulator and Android emulators. Physical-device access is not a release prerequisite. Record hardware-specific behavior as unverified and add physical-device checks when devices become available.

## Release scope

| Release | Contents | Dependency and branch policy |
| --- | --- | --- |
| `0.0.2-beta.N` then `0.0.2` | Existing composition/export API, clip and track speed, inherited visual filters, ordered audio EQ, and reliability fixes | Preserve the exact beta.4 tag as the candidate; retain stable Media3 1.11.1 |
| Next `0.1.0-alpha.N`, then `0.1.0-beta.N`, then `0.1.0` | Experimental composition and layer preview | Develop together on `develop`; merge only after both platform gates and stable dependency criteria pass |
| Later release, version to be assigned | Custom visual/audio effects, motion titles, animation extensions, masks and background removal | Develop on the same `develop` branch; release only after 0.0.2 |

Existing `0.1.0-alpha.*` tags remain unchanged. They are not renamed or promoted to `0.0.2`: these are different release lines. `0.0.2` is the stable installation recommendation. Preview users must explicitly select the preview prerelease.

## Development workflow

Use `develop` as the sole active development branch and one draft PR to `main`. It combines stabilization, preview, effects, motion titles, masks and optional segmentation. All Media3 modules on this branch use 1.12.0-alpha02. Keep known diagnostic failures visible and preserve the original test thresholds.

`main` stays stable. Existing release tags, including `0.0.2-beta.4` and every alpha, are immutable. Consolidating source does not create a release, restart beta.4 observation, or make the prerelease dependency suitable for stable users. Use the beta.4 tag for stable-candidate testing and its existing CI records for historical evidence. Any future candidate changes require focused verification and a new tag, never a moved tag.

## Maintainer acceptance


On November 21, the maintainer requested the stable 0.0.2 release and reported using beta.4 in Swideo without noticing problems. This is maintainer-reported application acceptance. Exact usage dates were not supplied, so this record does not claim that the previously proposed five-working-day observation window was independently verified. The promotion uses that acceptance together with the automated and independent-consumer evidence below.

The maintainer's earlier decision, "Ship with color limitation", accepts the measured bounded SDR color-conversion difference for 0.0.2. Keep the [measurements and scope](Testing.md#known-color-limitation) visible. This exception does not waive audio, timing, missing frames, alpha/opacity, filter, cancellation or cleanup regressions, and it does not establish a general color-fidelity guarantee.

## Current release evidence

[0.0.2-beta.4](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.4) is published at `311107384330d3c1670546b6eeef806447fdb0d9` with stable Media3 1.11.1. Its exact-commit [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42682862180) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42682863148) passed, including both example builds and all three coverage gates. macOS and iOS each passed 44 library tests; the editor passed six tests. Hosted API 34 instrumentation passed 47 tests in six suites, and native Android core passed 35 tests. The same 47 app tests passed locally on API 35. See [tests and coverage](Testing.md) for the measured scopes.

After publication, independent SwiftPM and native Kotlin/AAR consumers resolved the exact beta.4 tag to that commit and passed exports. The iOS Simulator SwiftPM consumer and API 35 Kotlin consumer exported the canonical eight-second title/image and captioned picture-in-picture scene at 1280x720, including clip/track speed and EQ. Candidate files were independently decoded with AVFoundation to verify frames, duration, dimensions and audio. Post-tag checks also passed fractional PCM trims and missing-input cleanup through the Kotlin wrapper.

Beta.4 fixes variable input offsets after fractional PCM trims. A regression against beta.3's unchanged implementation produced six assertions for silent starts and delayed fades. An independent Media3 1.11.1 control placed identical half-speed WAV trims at either 0 or 100 ms. Preparing the selected PCM range as a zero-origin WAV removed that variation in four controls. The bounded, cancellable preparation runs off the application looper and reuses identical ranges within an export. All 12 PCM16/float export cases, cancellation and failure/recovery checks pass. This CPU audio preparation does not change GPU visual rendering.

Earlier prerelease tags remain unchanged and are not eligible for stable promotion:

| Superseded beta | Release-blocking finding | Corrected in |
| --- | --- | --- |
| [beta.1](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.1) | Cancelling before the first video sample could crash Media3's duration-configured muxer | beta.2: guard the empty-track timeline marker while preserving one-frame duration |
| [beta.2](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.2) | Accessing `AVAudioEngine.mainMixerNode` before offline mode initialized RemoteIO and could abort after an audio-service RPC timeout | beta.3: enable offline mode before graph construction |
| [beta.3](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.3) | Fractional PCM trims could add silence and shift fades | beta.4: normalize selected PCM samples before export |

The empty-track failure originates in [InAppMp4Muxer.close](https://github.com/androidx/media/blob/1.11.1/libraries/transformer/src/main/java/androidx/media3/transformer/InAppMp4Muxer.java) writing a duration marker before [Mp4Writer](https://github.com/androidx/media/blob/1.11.1/libraries/muxer/src/main/java/androidx/media3/muxer/Mp4Writer.java) has reserved header space. SwiftVideo adds that marker only after a video keyframe and still closes the muxer on failure. No exact upstream fix is confirmed for that failure or the variable PCM offset.

`main` remains at the verified `0.0.2` release commit, `af71771`. Both platform CI workflows and published-tag SwiftPM, iOS and Kotlin/AAR consumers passed. The beta.4 tag remains unchanged. The accepted bounded SDR color limitation remains documented. It does not waive audio, timing, missing-frame or general filter regressions.

Before consolidation, [PR #1](https://github.com/shial4/SwiftVideo/pull/1) at `fb8b612` passes [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42685774218). Its [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42685774348) passes compilation, the example build and 40 native core tests, but instrumentation completes 75 tests with six assertions: four color checks and two missing-overlay checks in raw seek/reset controls with the frame processor disabled. Audio checks and the supported recreation path pass in this run. The Android CI coverage gate is skipped after the failure; local Media3 coverage is 89.51%. Preview is not eligible to merge.

[PR #6](https://github.com/shial4/SwiftVideo/pull/6) at `0626b8f` had no merge conflicts when reviewed. Its November 12 hosted Apple run and both Android build jobs passed. Android app tests recorded seven assertions: the six above plus the historically intermittent raw frame-processor seek failure. Supported preview paths and audio checks passed, but the failed instrumentation step skipped the Android coverage gate. See the [CI review](Testing.md#pr-6-hosted-ci-review). Keep the PR draft until the runtime/coverage and stable dependency gates pass; a historical raw control failure must not be relabeled as a passing test.

On November 22, stable `main` at `af71771` was merged into `develop`, resolving the workflow and release-document conflicts introduced by the 0.0.2 promotion. The development Android workflow and all six coverage thresholds remain unchanged. Custom visual/audio effects and motion titles now use the shared export callbacks in Android composition preview; Apple and Android layer snapshots accept the same visual registry and sample effects at the requested project time. See the [current verification](Testing.md#preview-and-effects-integration).

At final code commit `951297b`, [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/44997621619) passed. [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/44997621533) passed both builds and 71 native core tests, then completed all 138 app tests with the same seven hosted diagnostic assertions as the preceding `37764d6` run. The new preview/effect tests passed. Merge blockers remain the failed Android runtime gate, its skipped hosted coverage gate, and the prerelease Media3 dependency. Local API 35 runs also retained codec and playback-deadline failures; those did not recur in hosted API 34, but remain a verification risk requiring a focused check before a release candidate. Keep PR #6 draft and unmerged.

## Release gates

All required checks refer to the candidate's exact commit and resolved dependencies. A green result on an older alpha commit is not release evidence.

| Area | Required evidence |
| --- | --- |
| Apple | Complete macOS Swift Testing suites, editor model tests, all applicable iOS suites, and example build; no hangs or missing suites |
| Android | Native Swift core tests, real Media3 instrumentation exports, and example build on hosted API 34; targeted API 35 checks for the previously observed audio/timing failures |
| Coverage | At least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines, using the existing scopes |
| Behavior | Correct clip/track speed composition, pitch preservation, source ranges, filter order, timing, decoded overlays and audio; cancellation, cleanup and destination protection remain correct |
| Compatibility | Existing project JSON decodes; native Apple SwiftPM consumer and Skip example build and export; the documented Kotlin wrapper packaging and invocation smoke test passes |
| Runtime smoke checks | Use iOS Simulator and Android API 34/35 emulators for short exports covering image/title, picture-in-picture, captions, speed and EQ; record OS, architecture, codec, result and limitations. Physical-device testing is follow-up work when hardware is available |
| Dependencies | Release artifacts resolve without local patches or unpublished native libraries; stable releases use stable dependency versions |
| Documentation | API availability, examples, coverage date/scope, installation version and known limitations agree with the released tag |

Keep routine render fixtures at **320x180** with short durations. Retain decoded frame and PCM assertions; reducing resolution is not permission to reduce behavioral coverage. Use a small delivery-resolution simulator/emulator smoke export outside the routine suite. Do not impose full-HD work on every CI test.

Simulator/emulator results establish behavior in those environments. They do not establish hardware codec availability, vendor GPU/driver behavior, thermal limits or sustained throughput on phones. Keep these limits in the test documentation and release notes; lack of a physical device alone must not block beta or stable promotion.

Fix flaky tests or their underlying implementation. Do not retry until green, relax tolerances to conceal a failure, or reduce coverage thresholds. After changing a known intermittent path, repeat that focused scenario enough to assess the fix and retain every result; then run the full candidate suite once. If media behavior changes during beta, issue a new beta and restart its observation window. Documentation-only corrections need documentation checks.

After merging, rerun required checks if the merge produced a new SHA. Tag only a passing commit. If a released defect is found, preserve existing tags, document affected versions, and prepare a corrective patch; do not silently replace release artifacts.

## Known limitations and preview blockers

| Finding | What is established | Next action and release impact |
| --- | --- | --- |
| Preview dependency | The alpha uses Media3 1.12.0-alpha02. The attempted 1.11.1 preview path lacks the required builder/packaged native support | Keep the combined development PR draft. Test each relevant upstream candidate, then require stable, published dependencies before merging preview into `main`. Does not itself block the stable export branch |
| Paused seeking across gaps | Raw player variants can fail to display the expected overlay. Our recreate/coalesce adapter passed production-path tests on API 34, but broader evidence is incomplete | Reproduce both the public SwiftVideo path and raw control on API 34/35 emulators. Add phone coverage when available. Missing/stale frames in the supported public path remain blocking |
| Audio and timing | Published 0.0.2 contains beta.4's verified fractional PCM fix. Hosted preview audio checks pass, including custom-effect seeks; November 22 local API 35 codec and timing failures remain recorded | Complete focused API 35 verification before the next preview release candidate. Passing API 34 tests do not resolve the local failures; retain the seeking and dependency gates |
| BT.709 color on both release lines | The preview diagnostic found a shift before SwiftVideo effects. Stable candidate `7947b27` with Media3 1.11.1 also changed synthetic red from 255 to 231 on an API 34 arm64 emulator; an independent Apple decode confirmed a difference in the exported file | Accepted as a documented limitation for 0.0.2 on November 9. Retain the measurements and scope in release notes. Physical-device comparison is optional follow-up. Do not describe human visibility, hardware scope or an upstream fix as established |

The maintainer's decision, "Ship with color limitation", accepts the measured SDR color-conversion difference for 0.0.2. The reviewed evidence includes synthetic BT.709 patches and the bundled coastal example exported as H.264/AAC at 1280x720 on iOS 27.0 Simulator and Android API 34/35 arm64 emulators. The coastal example includes title/image overlays and captioned picture-in-picture. Its source is AI-generated artwork animated into video, not captured camera footage; this is a bounded sample, not comprehensive footage validation.

Keep the [diagnostic measurements](Testing.md#known-color-limitation) visible and physical-device scope marked unverified. This exception is nonblocking for 0.0.2; it does not establish a general color-fidelity guarantee. General color regressions, alpha/opacity errors, missing frames and broken filters remain failures. Existing pixel assertions and coverage thresholds are unchanged. Preview's other release gates remain in effect.

Upstream work to watch (status checked November 22, 2026):

- [Media3 #2439](https://github.com/androidx/media/issues/2439): open multi-sequence seeking issue. Maintainers describe active frame-processor work; no committed date for our exact failures.
- [Media3 #3470](https://github.com/androidx/media/pull/3470): GL-thread latch fix merged October 30 and included in [1.12.0-beta01](https://developer.android.com/jetpack/androidx/releases/media3#1.12.0-beta01), published November 11. This addresses a crash, not proof that missing-frame assertions are fixed. The latest stable version remains 1.11.1; beta01 does not satisfy the stable dependency gate.
- [Media3 #3482](https://github.com/androidx/media/issues/3482) and [#3483](https://github.com/androidx/media/pull/3483): paused no-op seek can flush audio; the proposed fix remains open. It is related to audio behavior, but not a confirmed explanation for our PCM/RMS failures.

No exact upstream ticket has been identified for the observed color conversion. Prepare a minimal reproduction with codec, device, input color metadata and raw output measurements before deciding where to report it. Do not wait for an unrelated issue to close as evidence of a fix.

The November 13 [beta01 candidate check](Testing.md#pr-6-hosted-ci-review) compiled and completed the full Android app suite, retaining four color and two raw seek/reset assertions. Its one passing frame-processor seek control does not resolve the historical intermittent failure. Keep alpha02 on `develop` for now; beta01 did not clear either the runtime or stable dependency gate. All original assertions remain enabled.

## Monitoring and promotion

Stable 0.0.2 was published on November 22, 2026. Preserve its tag and beta.4. New preview/effects candidates remain on `develop`; do not create a prerelease for every implementation commit.

Use this plan's blocker list and existing CI artifacts as the release record. For each candidate, record: SwiftVideo SHA/tag, resolved Media3 version, device/OS, test failures, coverage results, artifact links and the release decision. Keep raw logs and media in CI artifacts, not in source control.

Review upstream **weekly**, and again when a relevant Media3 version appears. This is the proposed operating cadence; no scheduled automation has been installed.

1. Check the [official release index](https://developer.android.com/jetpack/androidx/releases/media3) and linked issues/PRs. Record whether a fix is merely proposed, merged, published, or reproduced as passing locally.
2. For a relevant published version, update all related Media3 artifacts together on `develop`. Confirm dependency resolution and packaged native libraries before runtime testing.
3. Run the small seeking/audio/color reproductions first, then public preview/export tests. Run the full platform gates only after the targeted results justify promotion.
4. Keep routine fixes on `develop` without creating a release for each commit. Publish a prerelease only for an agreed testing milestone, and describe open failures explicitly.
5. Consider `0.1.0-beta.1` once public preview behavior passes on both platforms, the API is frozen, and the dependency is at least beta. Keep it off `main` while its dependency is prerelease.
6. Promote preview to stable only with stable dependencies, passing exact-commit CI and simulator/emulator checks, and at least five working days of beta use without release-blocking defects. A dependency reaching stable alone is insufficient.

Raw upstream controls and accepted diagnostic limitations may eventually be reported separately from supported API gates, but that classification must have evidence and an explicit documented contract. Existing failures remain visible; the combined development PR cannot be merged simply by relabeling failed tests.

## Timing and uncertainty

The 0.0.2 stabilization work is complete. The remaining schedule depends on preview verification and a suitable stable Media3 release.

For preview, the official Media3 history gives a planning range, not a fix commitment:

| Media3 version | First alpha | Stable | Elapsed |
| --- | --- | --- | --- |
| 1.9.0 | October 22, 2025 | December 17, 2025 | 56 days |
| 1.10.0 | February 6, 2026 | March 26, 2026 | 48 days |
| 1.11.0 | June 24, 2026 | August 5, 2026 | 42 days |

These [official release dates](https://developer.android.com/jetpack/androidx/releases/media3) suggest early-to-mid December 2026 for a possible 1.12 stable release, following its October 21 first alpha. Allow a January buffer. This is our inference; it does not establish when the seeking, audio or color issues will be resolved. Budget another 1-2 weeks for SwiftVideo preview verification and beta use after a suitable upstream build, assuming no further defects.

## Extensibility after stabilization

Implementation from [PR #5](https://github.com/shial4/SwiftVideo/pull/5) is consolidated with preview and stabilization history on `develop`. It is not part of beta.4 or the 0.0.2 release gate. Keep one development PR open; superseded PRs #1, #4 and #5 are closed. Do not promote `develop` as 0.0.2.

The branch implements versioned effect registration and validated parameters; Apple Core Image/Metal and Android GPU visual adapters; bounded custom audio DSP; word/grapheme motion titles and animation controls; GPU masks/chroma key; and optional person segmentation using existing models. Examples and usage guides accompany the APIs. At `01f70f1`, [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42684980302) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42684980550) pass, including optional-module coverage gates.

| Work | Implemented on develop | Remaining verification |
| --- | --- | --- |
| Registration and contracts | Versioned identifiers, Codable parameters, validation, ordering, platform checks and lifecycle | Release review and broader application integration |
| Custom GPU visual effects | Apple Core Image/Metal processors, Android GLSL and typed native Media3 adapters | Physical GPU compatibility and sustained performance |
| Custom audio effects | Shared Swift PCM processors, reset/seek lifecycle and gain/echo examples | Broader application integration |
| Motion titles and animations | Word/character presets, custom timing, curves, repetition and custom fonts | Broader script/font coverage and performance |
| Masks and chroma key | GPU rectangle/ellipse masks and chroma-key removal | Broader footage and device coverage; image-mask textures remain outside this increment |
| AI background removal | Optional Vision/Core ML and MediaPipe person segmentation for images and video | Physical Android GPU inference, model quality and sustained performance |
| Tests and documentation | Real simulator/emulator exports, failure/recovery tests, separate coverage gates, independent SwiftPM/Kotlin consumers, usage guides and an Apple time/memory diagnostic | Release review, broader application usage and sustained performance measurements |

See [custom effects](CustomEffects.md) and [person segmentation](PersonSegmentation.md) for usage and model/compute limits.

Remaining release work is review and promotion after 0.0.2, with final consumer checks at the release candidate. Physical-device GPU inference, vendor drivers, thermal behavior and sustained phone throughput remain unverified follow-up work. Person segmentation does not promise arbitrary-subject removal or motion-aware video matting. The development PR records its API and rendering limits. The original engineering estimates describe the proposed work; they are not remaining effort now that implementation exists.
