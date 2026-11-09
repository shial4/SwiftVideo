<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# SwiftVideo release plan

[Documentation index](README.md) | [Tests and coverage](Testing.md)

Reviewed November 10, 2026. Stabilize the existing library for **0.0.2 first**, continue experimental preview separately, and add extensibility afterward. This scope supersedes the earlier proposal to include extensibility in 0.0.2.

At the maintainer's request, release verification uses the iOS Simulator and Android emulators. Physical-device access is not a release prerequisite. Record hardware-specific behavior as unverified and add physical-device checks when devices become available.

## Release scope

| Release | Contents | Dependency and branch policy |
| --- | --- | --- |
| `0.0.2-beta.N` then `0.0.2` | Existing composition/export API, clip and track speed, inherited visual filters, ordered audio EQ, and reliability fixes | Start `codex/stabilize-0.0.2` from `main`; retain stable Media3 1.11.1 |
| Next `0.1.0-alpha.N`, then `0.1.0-beta.N`, then `0.1.0` | Experimental composition and layer preview from PR #1 | Keep the preview branch separate; merge only after both platform gates and stable dependency criteria pass |
| Later release, version to be assigned | Custom visual/audio effects, motion titles, animation extensions, masks and background removal | Develop separately on `codex/effect-extensibility`; release after 0.0.2 |

Existing `0.1.0-alpha.*` tags remain unchanged. They are not renamed or promoted to `0.0.2`: these are different release lines. `0.0.1` remains the stable installation recommendation until 0.0.2 is published. Preview users must explicitly select the preview prerelease.

## Starting evidence

November 10 PCM timing hold: beta.3 is not eligible for stable promotion. A new repeated-export regression against its unchanged Android implementation reproduced added silence at a fractional PCM trim and a delayed fade (six assertions failed across the short controls). An independent Media3 1.11.1 control traced identical half-speed WAV trims entering the mixer at either 0 or 100,000 microseconds. Independently decoded files confirmed the shifted fade. Pre-trimming the selected PCM samples to a zero-origin WAV removed the variable offset in four controls. A bounded, cancellable preparation fix is under verification; it retains the stable dependency and does not alter the accepted color limitation. Publish a new beta only after the full release gates pass, then start a fresh observation window.

November 10 promotion hold: [Apple CI on the extensibility branch](https://github.com/shial4/SwiftVideo/actions/runs/42649175256) exposed a shared offline-audio initialization defect. Accessing `AVAudioEngine.mainMixerNode` before enabling manual rendering initialized RemoteIO; an audio-service RPC timeout aborted the simulator test process. The same order exists in beta.2. Backport `0f9ca44` enables offline mode before attaching or connecting nodes, following the SDK's documented initialization guidance. The backport passes 44 macOS tests and 44 iOS Simulator tests locally, with 95.39% iOS line coverage. [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42654173233) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42654173280) passed at `b51a1ed35c03c718b73037c4b4a147bf07ca159c`. Independent SwiftPM and Kotlin/AAR exports passed both before publication and after resolving the exact `0.0.2-beta.3` tag to that commit; the Kotlin consumer also passed missing-input cleanup on API 35. [Beta.3](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.3) replaces beta.2, which remains ineligible for stable promotion. Earlier tags remain unchanged.

November 10 follow-up: [0.0.2-beta.2](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.2) is published at `89c0709739ee1724d1186ea1ad06696770dd338a`, superseding beta.1. With Media3 1.11.1, beta.1 could terminate the Android application if cancellation closed a duration-configured video muxer before its first sample (`IllegalArgumentException: capacity < 0: (-8 < 0)`). The guarded timeline muxer is backported as `c81d6ab`. Local checks pass: 44 macOS tests, 44 iOS Simulator tests, six editor model tests, and API 35 suites with 35 core tests and 44 app tests. Both example builds and all three coverage gates pass. [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42644747438) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42644747467) passed for the published commit. Independent SwiftPM and Kotlin/AAR consumers also passed against that revision. Beta.1's release notes now identify the crash and direct users to beta.2; its tag is unchanged. The later offline-audio finding above now blocks its promotion; see the current observation status below.

The relevant upstream path is [InAppMp4Muxer.close](https://github.com/androidx/media/blob/1.11.1/libraries/transformer/src/main/java/androidx/media3/transformer/InAppMp4Muxer.java), which writes an empty duration marker, followed by [Mp4Writer's moov update](https://github.com/androidx/media/blob/1.11.1/libraries/muxer/src/main/java/androidx/media3/muxer/Mp4Writer.java) before any sample has reserved header space. No matching upstream fix has been confirmed. SwiftVideo's workaround adds the duration marker only after a video keyframe has been written and still closes the underlying muxer on failure. It retains Media3's default attempt to place metadata before media for sequential playback.

`main` is at `d2977a2` with stable Media3 1.11.1. Candidate `7947b27` in [PR #4](https://github.com/shial4/SwiftVideo/pull/4) contains the focused backports and a one-frame export fix. Its [November 9 local verification](Testing.md) passes macOS, iOS Simulator and Android API 34/35 emulator tests, both example builds, and all three coverage gates. [Hosted Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42527055392) and [hosted Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42527055454) also passed for that commit. Standalone SwiftPM and Kotlin/AAR consumer exports pass. On November 9, the maintainer accepted the measured color limitation for 0.0.2. Those checks preceded beta.1; the November 10 blocker above supersedes its promotion status. PR #4 and the release notes record each candidate's final CI results.

[PR #1](https://github.com/shial4/SwiftVideo/pull/1) is draft at `c9577c1`. Its [Apple CI run passed](https://github.com/shial4/SwiftVideo/actions/runs/42112198363); its [Android CI run failed](https://github.com/shial4/SwiftVideo/actions/runs/42112198340). Android core tests passed, but instrumentation recorded four color assertions and three raw paused-seek assertions. The Android coverage gate did not execute after that failure. These results do not establish a passing 0.0.2 candidate.

## Implementation sequence

Estimates assume one engineer, existing toolchains and simulator/emulator runtimes, and no newly discovered major regression. Codex owns implementation, diagnostics and release preparation; the maintainer owns product acceptance. Existing authorization to merge after the release gates pass remains in effect.

| Step | Work | Exit condition | Engineering effort |
| --- | --- | --- | --- |
| 1. Prepare stable candidate | Create the release branch from `main`; backport the Apple blocking-media fix and focused test/coverage improvements | Reviewed diff contains stable features and dependencies only | 0.5-1 day |
| 2. Verify and fix | Run the complete Apple and Android suites; investigate any failure on this branch before attributing it to preview or upstream | Required tests and coverage pass; no unexplained failures | 2-4 days |
| 3. Verify consumers and runtimes | Exercise the title/image and captioned picture-in-picture examples, speed/filter combinations, and documented integration paths | Candidate passes on iOS Simulator and Android API 34/35 emulators; documentation states the tested environments and limitations | 1-2 days |
| 4. Publish and observe beta | Tag a passing candidate as `0.0.2-beta.N`; exercise it through actual package consumers and record findings | Five working days of beta use with no open release-blocking defect | 0.5-1 day, plus observation window |
| 5. Release | Merge the passing candidate, verify the resulting `main` SHA, tag `0.0.2`, publish matching notes and update installation guidance | Published tag resolves to the tested commit; package consumer smoke checks pass | 0.5-1 day |

Step 1 reuses these focused changes:

- `c9577c1`: run blocking Apple decoder/audio work on a dedicated serial executor and test it through that executor.
- `b29374f`: run every applicable Apple suite and retain useful diagnostics when a runner stalls.
- `39c1b84`: collect iOS coverage from the tested binary and matching profiles. Bring the collector and workflow change, not preview-specific release statements.
- `c65d2a9`: clean only the Android runtime directory created by the test invocation, after collecting results.
- `40e56f9`: set the Android muxer's video endpoint so one-frame exports retain their duration. The stable-branch regression reproduced 0 ms output before the fix and passed afterward on API 34 and 35.

Local verification also required the LLVM coverage parser used by the collector and replacement of read-only generated Android coverage inputs during repeated packaging. Native core test stderr is now retained in the test artifact.

Keep the current Swift, Skip and Android toolchains. Do not install a redundant local Swift toolchain, change Skip modes, or introduce new rendering abstractions for stabilization. Bring additional CI changes only when a candidate failure or measured build bottleneck justifies them.

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
| Preview dependency | The alpha uses Media3 1.12.0-alpha02. The attempted 1.11.1 preview path lacks the required builder/packaged native support | Keep PR #1 draft. Test each relevant upstream candidate, then require stable, published dependencies before merging preview into `main`. Does not itself block the stable export branch |
| Paused seeking across gaps | Raw player variants can fail to display the expected overlay. Our recreate/coalesce adapter passed production-path tests on API 34, but broader evidence is incomplete | Reproduce both the public SwiftVideo path and raw control on API 34/35 emulators. Add phone coverage when available. Missing/stale frames in the supported public path remain blocking |
| Audio and timing | Fractional PCM trims in stable beta.3 reproduce silent starts and delayed fades; an independent Media3 1.11.1 control reproduces variable input offsets. Preview also has unresolved timing evidence | Verify the bounded PCM-preparation fix on both platforms and in independent consumers, then publish a new beta. Beta.3 cannot be promoted. Recheck preview after the shared fix |
| BT.709 color on both release lines | The preview diagnostic found a shift before SwiftVideo effects. Stable candidate `7947b27` with Media3 1.11.1 also changed synthetic red from 255 to 231 on an API 34 arm64 emulator; an independent Apple decode confirmed a difference in the exported file | Accepted as a documented limitation for 0.0.2 on November 9. Retain the measurements and scope in release notes. Physical-device comparison is optional follow-up. Do not describe human visibility, hardware scope or an upstream fix as established |

The maintainer's decision, "Ship with color limitation", accepts the measured SDR color-conversion difference for 0.0.2. The reviewed evidence includes synthetic BT.709 patches and the bundled coastal example exported as H.264/AAC at 1280x720 on iOS 27.0 Simulator and Android API 34/35 arm64 emulators. The coastal example includes title/image overlays and captioned picture-in-picture. Its source is AI-generated artwork animated into video, not captured camera footage; this is a bounded sample, not comprehensive footage validation.

Keep the [diagnostic measurements](Testing.md#known-color-limitation) visible and physical-device scope marked unverified. This exception is nonblocking for 0.0.2; it does not establish a general color-fidelity guarantee. General color regressions, alpha/opacity errors, missing frames and broken filters remain failures. Existing pixel assertions and coverage thresholds are unchanged. Preview's other release gates remain in effect.

Upstream work to watch:

- [Media3 #2439](https://github.com/androidx/media/issues/2439): open multi-sequence seeking issue. Maintainers describe active frame-processor work; no committed date for our exact failures.
- [Media3 #3470](https://github.com/androidx/media/pull/3470): GL-thread latch fix merged October 30, after alpha02. Confirm inclusion in a published artifact and rerun our reproduction; this addresses a crash, not proof that missing-frame assertions are fixed.
- [Media3 #3482](https://github.com/androidx/media/issues/3482) and [#3483](https://github.com/androidx/media/pull/3483): paused no-op seek can flush audio; the proposed fix remains open. It is related to audio behavior, but not a confirmed explanation for our PCM/RMS failures.

No exact upstream ticket has been identified for the observed color conversion. Prepare a minimal reproduction with codec, device, input color metadata and raw output measurements before deciding where to report it. Do not wait for an unrelated issue to close as evidence of a fix.

## Monitoring and promotion

The latest published stable-line beta is [0.0.2-beta.3](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.3), published November 10, 2026 at 03:24 Australia/Brisbane (November 9 at 17:24 UTC), at `b51a1ed35c03c718b73037c4b4a147bf07ca159c`. The original exact-tag SwiftPM and Kotlin/AAR consumer checks pass, but the subsequent PCM timing regression above blocks promotion. November 11-17 was the proposed observation window; it is superseded until a corrected beta passes the gates and its actual-use dates are recorded. Do not promise November 18 as a release date. Elapsed time alone is not evidence of beta use. Keep [PR #4](https://github.com/shial4/SwiftVideo/pull/4) draft during observation. A new media-behavior fix requires a new beta and a fresh window. The beta.1, beta.2 and beta.3 windows are superseded; none of those releases is promotable.

Use this plan's blocker list and existing CI artifacts as the release record. For each candidate, record: SwiftVideo SHA/tag, resolved Media3 version, device/OS, test failures, coverage results, artifact links and the release decision. Keep raw logs and media in CI artifacts, not in source control.

Review upstream **weekly**, and again when a relevant Media3 version appears. This is the proposed operating cadence; no scheduled automation has been installed.

1. Check the [official release index](https://developer.android.com/jetpack/androidx/releases/media3) and linked issues/PRs. Record whether a fix is merely proposed, merged, published, or reproduced as passing locally.
2. For a relevant published version, update all related Media3 artifacts together on an isolated candidate branch. Confirm dependency resolution and packaged native libraries before runtime testing.
3. Run the small seeking/audio/color reproductions first, then public preview/export tests. Run the full platform gates only after the targeted results justify promotion.
4. Publish another `0.1.0-alpha.N` while behavior or packaging remains experimental. Describe open failures explicitly.
5. Consider `0.1.0-beta.1` once public preview behavior passes on both platforms, the API is frozen, and the dependency is at least beta. Keep it off `main` while its dependency is prerelease.
6. Promote preview to stable only with stable dependencies, passing exact-commit CI and simulator/emulator checks, and at least five working days of beta use without release-blocking defects. A dependency reaching stable alone is insufficient.

Raw upstream controls and accepted diagnostic limitations may eventually be reported separately from supported API gates, but that classification must have evidence and an explicit documented contract. Existing failures remain visible; PR #1 cannot be merged simply by relabeling failed tests.

## Timing and uncertainty

For **0.0.2**, budget roughly **5-9 engineering days plus the beta observation window**, usually **2-3 calendar weeks**. Reassess after the first complete stable-branch Android run. A reproducible production regression can extend this estimate; Media3 preview development need not be on this release's critical path.

For preview, the official Media3 history gives a planning range, not a fix commitment:

| Media3 version | First alpha | Stable | Elapsed |
| --- | --- | --- | --- |
| 1.9.0 | October 22, 2025 | December 17, 2025 | 56 days |
| 1.10.0 | February 6, 2026 | March 26, 2026 | 48 days |
| 1.11.0 | June 24, 2026 | August 5, 2026 | 42 days |

These [official release dates](https://developer.android.com/jetpack/androidx/releases/media3) suggest early-to-mid December 2026 for a possible 1.12 stable release, following its October 21 first alpha. Allow a January buffer. This is our inference; it does not establish when the seeking, audio or color issues will be resolved. Budget another 1-2 weeks for SwiftVideo preview verification and beta use after a suitable upstream build, assuming no further defects.

## Extensibility after stabilization

This work remains separate from 0.0.2 and is not part of its release gate. Development continues on `codex/effect-extensibility` while the stable beta is observed; it must not be merged into the stabilization branch.

1. Define a small effect contract: identity and version, validated Codable parameters, supported platforms, ordering, resource lifetime, cancellation and explicit unsupported-effect errors. Preserve the existing built-in effects and project compatibility.
2. Add a custom visual-effect adapter on each platform. Keep frame processing on Core Image/Metal and Media3/OpenGL; avoid per-frame GPU-to-CPU copies. Prove it with one custom effect on both platforms before expanding the API.
3. Add reusable motion-title and animation presets using the existing fonts and whole-layer keyframes. Treat per-glyph layout/animation as separate work with explicit platform parity tests.
4. Add a bounded audio-processing extension with defined sample format, state/reset rules and scheduling. Audio DSP may remain on CPU where that is the appropriate backend; do not promise GPU execution for arbitrary audio effects.
5. Add mask/chroma-key support, then evaluate ML segmentation as an optional capability with explicit quality, model, device and performance constraints.

The original estimate was **6-8 engineer-weeks for useful extensibility**, or **10-16 weeks total for the broader feature set including segmentation with existing models**. The November 10 development status is:

| Work | Implemented on the feature branch | Remaining verification |
| --- | --- | --- |
| Registration and contracts | Versioned identifiers, Codable parameters, validation, ordering, platform checks and lifecycle | Release review and broader application integration |
| Custom GPU visual effects | Apple Core Image/Metal processors, Android GLSL and typed native Media3 adapters | Physical GPU compatibility and sustained performance |
| Custom audio effects | Shared Swift PCM processors, reset/seek lifecycle and gain/echo examples | Broader application integration |
| Motion titles and animations | Word/character presets, custom timing, curves, repetition and custom fonts | Broader script/font coverage and performance |
| Masks and chroma key | GPU rectangle/ellipse masks and chroma-key removal | Broader footage and device coverage; image-mask textures remain outside this increment |
| AI background removal | Optional Vision/Core ML and MediaPipe person segmentation for images and video | Physical Android GPU inference, model quality and sustained performance |
| Tests and documentation | Real simulator/emulator exports, failure/recovery tests, separate coverage gates, independent SwiftPM/Kotlin consumers, usage guides and an Apple time/memory diagnostic | Latest hosted CI, broader application usage and sustained performance measurements |

See [tests and coverage](Testing.md#optional-segmentation-module) for measured results and [person segmentation](PersonSegmentation.md) for model and compute limits. Implemented does not mean released or fully verified: these features are absent from `main` and the 0.0.2 betas. Physical-device checks remain follow-up work when hardware becomes available, consistent with the agreed simulator/emulator release scope.
