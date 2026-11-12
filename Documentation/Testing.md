<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Tests and coverage

[Documentation index](README.md) | [Public API reference](APIReference.md)

## Combined development verification

The merged `develop` implementation was tested locally on November 10, 2026, and its results reviewed on November 13. It combines stabilization head `b0179f4`, extensibility head `1e4a6aa`, and preview head `fb8b612`. No release tag was created or moved. This is consolidation evidence, not a stable release pass.

| Target | Observed result | Measured coverage |
| --- | --- | --- |
| macOS library | 117 tests in 18 suites passed | Real exports and core behavior |
| iOS 27 Simulator | 116 tests in 18 suites passed | 2,383 / 2,464 lines, 96.71% |
| Android native core | 69 tests in 10 suites passed | 1,593 / 1,680 lines, 94.82% |
| Android API 35 arm64 app | 132 tests in 16 suites completed; six known diagnostic assertions on recheck | Media3: 1,825 / 2,046 generated lines, 89.20% |
| Optional segmentation | Image/video and failure/recovery checks passed | iOS 137/168 (81.55%); native Android 37/41 (90.24%); Media3 161/179 (89.94%) |
| Example editor | Six model tests and both platform app builds passed | No UI coverage claim |

All six existing coverage thresholds pass when processing these local profiles. Android instrumentation remains a failed suite: four BT.709 color assertions and two raw-player seek/reset assertions match the preview baseline. The first combined run recorded those six issues plus one audio-preview startup timeout (`red-with-offset-music.mp4`, zero source trim) while example builds were running. The unchanged APK recheck, without competing builds, completed in 235.190 seconds with all audio checks passing and the original six issues. The first timeout remains recorded as an intermittent verification risk; the recheck does not establish its cause or erase it.

Merge regressions verify that layer masks use source coordinates before crop and that unsupported custom effects/motion titles fail before writing a preview. Export retains the custom visual/audio and motion-title callbacks through the shared Android composition builder. Layer previews support built-in masks and chroma key; custom registry and motion-title preview integration remains unsupported.

The checked-in [iOS](Coverage/ios.json), [Android core](Coverage/android-core.json), and [Media3](Coverage/android-media3.json) files are this combined local snapshot. Exact-commit hosted CI must be assessed on the development PR; historical passing CI below does not verify this merge. Existing installed toolchains were used, with no local toolchain installation or package-version upgrade.

## Frozen beta.4 evidence

The [0.0.2-beta.4](https://github.com/shial4/SwiftVideo/releases/tag/0.0.2-beta.4) snapshot was verified on November 10, 2026, at `311107384330d3c1670546b6eeef806447fdb0d9` with Media3 1.11.1. Exact-commit [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42682862180) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42682863148) pass, including example builds and all coverage gates. The 0.0.1 tag predates playback speed and ordered filters. Beta observation remains a separate release gate; see the [release plan](ReleasePlan.md).

| Target | Observed result | Coverage |
| --- | --- | --- |
| macOS library | 44 tests, 6 suites passed | Integration and core behavior |
| iOS Simulator | 44 tests, 6 suites passed | 1,469 / 1,540 lines, 95.39% |
| Android API 34 hosted / API 35 local instrumentation | 47 tests, 6 suites passed on each | Real Media3 exports and native Swift tests |
| Android native Swift core | 35 tests, 4 suites passed | 921 / 960 lines, 95.94% |
| Android Media3 bridge | Hosted instrumentation coverage | 578 / 635 generated lines, 91.02% |
| Example editor model on macOS | 6 tests passed | Asset loading, edits, history, selection, failure handling |

The beta.4 coverage reports remain available at its immutable tag. Coverage files on `develop` describe the combined implementation recorded above; they must not be treated as beta.4 evidence. Workflow badges link to live CI.

Independent SwiftPM and native Kotlin/AAR consumers passed before publication and after resolving exact `0.0.2-beta.4` to the SHA above. The macOS consumer exported a title with combined clip/track speed and filters. A separate iOS 27.0 Simulator package consumer exported the eight-second canonical example and decoded frames at 0, 1, 3, 5 and 7 seconds. The API 35 arm64 Kotlin consumer passed three tests covering export and missing-input cleanup, fractional PCM source ranges, and the same canonical example. Post-tag iOS smoke took 2.425 seconds and the three Kotlin tests took 15.770 seconds; these are emulator/simulator observations, not phone benchmarks.

The original 0.0.1 manual editor checks covered macOS, iOS Simulator, and Android Emulator. That historical Android export was independently decoded as an eight-second 1920x1080 MP4. Current routine tests use 320x180; release smoke checks use 1280x720. An earlier unsigned Release build for physical iPhones compiled, but has not been run on hardware.

## Preview baseline before consolidation

At `fb8b612`, [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42685774218) passed 56 macOS and 56 iOS tests and six editor tests. [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42685774348) passed compilation, the example build and 40 native core tests. Instrumentation completed 75 tests with six assertions: four BT.709 color checks and two missing-overlay checks in raw CompositionPlayer seek/reset controls. The supported recreation path and all audio checks passed. This is not a passing Android release gate; CI coverage processing was skipped after instrumentation failed. The same six assertions occurred locally on API 35.

The development branch retains Media3 1.12.0-alpha02 because 1.11.1 lacks the required preview builder and a published native helper artifact. Stable adoption requires compatible stable dependencies and passing platform gates. Existing diagnostic thresholds remain unchanged; see the [release plan](ReleasePlan.md#known-limitations-and-preview-blockers).

## What the tests verify

- Rational frame/time arithmetic, overflow, input validation, and JSON round trips.
- Builder loops, branches, reusable arrays, thrown errors, stable IDs, immutable modifiers, and bounded text allocation.
- Atomic edits, missing targets, failed-batch rollback, split/trim source ranges, animation continuity, and audio envelopes.
- Export progress, cancellation, cleanup after failure, unsupported capabilities, and protection of existing destinations.
- Independently decoded real exports: duration, dimensions, frame changes, filters, crop, stacking, image opacity, text/animation, audio energy, stereo pan, and fades.
- One-frame Android MP4 exports retain their requested 25 ms or 33.33 ms duration and decode the expected image. The regression test reproduced zero-duration output before the muxer endpoint fix.
- Empty Android video tracks close safely after early cancellation; normal exports retain their requested final duration.
- Android fixture copies have independent file contents, so parallel tests cannot overwrite media another test is decoding.

The media fixtures are deterministic red/blue videos, a green image, and synthesized audio. Pixel and PCM measurements use platform decoders independently of the compositor. Tests allow codec/color conversion tolerances; they do not compare byte-identical compressed files across platforms.

Android Media3 rendering and source-frame decoding share the serialized `RenderBehaviorTests` suite so concurrent tests do not compete for the hosted emulator's graphics and codec resources. Core and fixture file-copy tests remain parallel.

Routine composition tests on both platforms render at 320x180. They verify decoded pixels, overlay placement, relative text motion, timing, and audio fades with much less rendering work than a full HD export. The beta.4 release smoke checks exported the eight-second title/image and captioned picture-in-picture example at 1280x720 and 30 fps with H.264 video and AAC audio on iOS 27.0 Simulator and the Android API 35 arm64 emulator. These checks used clip 2x and track 0.5x audio rates together with a 1000 Hz low-pass filter. iOS used an independent SwiftPM consumer; Android used the same canonical scene through the public Swift API and a native Kotlin consumer. Candidate outputs were independently decoded with AVFoundation for dimensions, duration, frames and non-silent audio. Earlier stable-line checks also covered the API 34 arm64 emulator.

CI compiles Android binaries on macOS and runs them on an Ubuntu KVM emulator with two virtual CPU cores and 4 GB of RAM. Emulator 36.6.11 is pinned to match the version used for local verification. CI uses the same composition tests and Media3 timeout as local tests. The complete device-test command has a fifteen-minute deadline, with thirty seconds to collect diagnostics before forced termination. Individual test assertions and timeouts are unchanged.

Platform-specific renderer failure, text-orientation and PCM preparation tests account for differences in test counts. The orientation test independently checks an asymmetric glyph in decoded output; it reproduced the iOS inversion before the fix and passes on both Apple targets. The Android instrumentation runner appears as one JUnit wrapper; `swt-events.jsonl` records the individual Swift Testing results.

## Coverage scope and gates

CI requires at least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines.

The iOS report includes executable first-party `Sources/SwiftVideo` code for that target, including the Apple renderer. The collector uses the tested binary's LLVM mapping and profiles for the result bundle's devices, because Xcode's `xccov` summary can omit package sources. The report parser also accepts `xccov` input and checks duplicate package/product entries for consistency.

Android core coverage runs an instrumented native Swift test process without a JVM. `SWIFTVIDEO_CORE_COVERAGE` excludes real Android media tests from this process. The Android renderer facade is excluded from this specific percentage because it needs an initialized Android app/JVM; it is exercised by the separate instrumentation suite. The native core percentage must not be described as coverage of the entire Android backend.

JaCoCo measures the generated Kotlin bytecode for the Swift-authored `SwiftVideoMedia3` implementation. It is a separate measurement, not Swift source-line coverage. Dependencies, generated bridge support, fixtures, tools, and the example UI are excluded from the library percentages. The three percentages are not averaged.

## Optional segmentation module

The unreleased `develop` branch includes separate coverage gates for `SwiftVideoSegmentation`: 75% Apple source lines, 90% Android native source lines, and 75% `SwiftVideoSegmentationMedia3` generated bytecode lines. These are independent of the three existing core-library gates and are never averaged with them. The iOS scope includes the Vision adapter even though that system model cannot run in the simulator; macOS tests exercise it with real inference.

At implementation commit `01f70f16b693152b92c9f1724a114941dde4e1f5`, [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42684980302) and [Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42684980550) pass, including example builds and every coverage gate. Apple runs 103 macOS and 102 iOS test functions; Android native core runs 64. Local API 35 instrumentation passes 102 functions in 14 suites after the shared PCM fix. Real image and video tests retain the person, remove the background, and recover after missing/corrupt model errors. The normal SwiftVideo Android runtime dependency graph contains no segmentation module or MediaPipe runtime.

| Hosted CI coverage scope | Covered / executable lines | Coverage | Gate |
| --- | --- | --- | --- |
| iOS core library | 2,266 / 2,342 | 96.75% | 90% |
| iOS optional segmentation | 137 / 168 | 81.55% | 75% |
| Android native core | 1,529 / 1,573 | 97.20% | 90% |
| Android native segmentation | 37 / 41 | 90.24% | 90% |
| Android Media3 bridge | 911 / 1,014 | 89.84% | 75% |
| Android segmentation bridge | 161 / 179 | 89.94% | 75% |

These CI measurements cover the extensibility implementation, not the stable beta. The earlier feature reports are attached to the linked CI runs; checked-in JSON files now describe the combined local snapshot above. The separate macOS segmentation measurement is 160/169 executable lines (94.67%), including real Vision inference. Android native segmentation coverage excludes the JVM process; its uncovered native factory calls are exercised in the app suite. The stable-first release order still applies despite passing feature CI. These historical consumer results predate consolidation and do not verify the combined branch.

Independent consumers resolved exact revision `931ea199b7bf0831149f281c628e722301d8e5a6`, whose library implementation matches the passing CI commit above. The native macOS SwiftPM consumer exported ten sequential clips with a compiled Core ML model and one clip with the raw model, checking decoded foreground/background pixels in every clip and total duration. A separate iOS 27.0 Simulator SwiftPM consumer passed a three-clip export with the same per-clip pixel/duration checks in 2.922 seconds. The rebuilt native Kotlin/AAR consumer passed its three-clip check on API 35 arm64 with no skips or failures (1.856 seconds reported by the test runner). All three consumers also verified missing-model cleanup and a successful export afterward through the same service. They use independent package/application targets; these are short integration checks, not phone throughput benchmarks.

The first Android packaging attempt encountered stale Kotlin internal-visibility metadata; cleaning only the generated Media3 module allowed the same source to build. The new iOS consumer initially failed to sign its fixture bundle before tests ran; copying the fixture files individually corrected its layout. Neither required a library source change. Existing installed toolchains and models were used. The [segmentation guide](PersonSegmentation.md#performance-and-verification) retains the separately measured Apple time/memory diagnostic at its original revision.

Apple tests use the app-supplied DeepLabV3 Core ML model on iOS Simulator and also exercise the system Vision model on macOS. Android emulator tests explicitly use CPU inference because the emulator GL translator rejects the MediaPipe GPU delegate's shader-storage-buffer query. Downsampling and compositing still run through the production GPU path. Physical-device GPU inference and sustained phone performance remain unverified. See [person segmentation](PersonSegmentation.md) for the exact model, memory-transfer and quality limits.

## Reproduce Apple tests

From the repository root:

```sh
swift test --build-system native --disable-xctest --enable-code-coverage
swift test --build-system native --package-path Example --disable-xctest
swift Tools/CheckHeaders.swift
```

For iOS, use the `xcodebuild` command in [apple.yml](../.github/workflows/apple.yml), selecting an installed simulator. It runs all applicable suites and writes an `.xcresult`. [CollectIOSCoverage.sh](../Tools/CollectIOSCoverage.sh) requires a passing, nonempty result, exports matching LLVM coverage, and enforces the iOS threshold through `Tools/Coverage.swift`.

Local verification used Xcode 27.2, the iOS 27.0 Simulator, and macOS 26.6.2. CI selects Xcode 26.6 on `macos-26`. Apple video tests require a Metal-capable rendering environment. Blocking decoder and offline audio operations run on the renderer's dedicated serial executor.

## Reproduce Android tests

The complete commands live in [android.yml](../.github/workflows/android.yml). Use an existing Skip installation with a matching Swift Android toolchain/SDK. The local verification configuration is Swift 6.3.2, NDK r27d, Gradle 9.8.2, and an API 34 arm64 emulator. Hosted CI cross-compiles x86_64 Android binaries on `macos-26-intel`, then transfers them to `ubuntu-24.04` for execution. Xcode's compiler builds host metadata, including the Apple AVKit preview; Swift 6.3.2 builds Android binaries. The emulator runner needs only ADB and the packaged binaries; it does not install Swift. On Apple Silicon development machines, use `--arch aarch64` for native builds, `ANDROID_ARCH=aarch64` when packaging, and an arm64 emulator.

The workflow has three jobs: `build` packages the test binaries, `tests` runs after `build`, and `example` builds the editor independently. The example no longer delays the emulator tests. Both macOS jobs use the same [setup action](../.github/actions/setup-android/action.yml), which caches the pinned toolchains and SwiftPM downloads. Gradle manages its dependency and task caches; cache writes are also enabled for same-repository PRs and the development branch. Generated Skip bridges and native incremental build directories are rebuilt from source. Toolchain caches have exact version/setup keys; SwiftPM caches are separated by build job and dependency manifests.

The test jobs perform these steps in order:

1. Generate Skip metadata with `SKIP_DYNAMIC_LIBRARIES=1 xcrun swift build --build-system native --scratch-path .build-media3 --target SwiftVideoTests`.
2. Build the native `SwiftVideo` library and Swift Testing bundle into the generated module's JNI directories.
3. [BuildAndroidTests.sh](../Tools/BuildAndroidTests.sh) builds the instrumented native core executable, runtime libraries, and Media3 test APK, and replaces their generated coverage inputs so read-only files from a prior run do not break packaging. The macOS job also compiles the example editor APK.
4. On the emulator host, [TestAndroid.sh](../Tools/TestAndroid.sh) runs the core executable and Android instrumentation APK, pulls native profiles and JaCoCo data, and retains core output, Swift Testing events and logcat even when a test fails. It removes its copied runtime directory after collecting profiles and on failure. It checks the JUnit result explicitly because Android's instrumentation command can exit zero after test failures.
5. Process the core profiles with the matching NDK `llvm-profdata` and `llvm-cov`, generate the Media3 JaCoCo XML report, and enforce both Android coverage gates.

For local use after generating metadata and building the JNI libraries, set `ANDROID_MODULE` to the generated `SwiftVideo` Gradle module and `SWIFT_VERSION` to the installed version. Run `bash Tools/BuildAndroidTests.sh`, then `bash Tools/TestAndroid.sh` with an emulator connected. Both scripts accept `ANDROID_TEST_ARTIFACTS` to override the default `.build-android-tests` directory. Standard `ANDROID_SERIAL` selects a specific connected device.

Use the NDK LLVM tools matching the Swift Android SDK. A different LLVM version can reject its profile format. On a host with a newer incompatible Apple SDK, select a compatible host SDK using process-scoped `DEVELOPER_DIR` and `SDKROOT`; no global Xcode setting is required.

For a CI instrumentation failure, download the `android-test-results` artifact. `android/swt-events.jsonl` identifies individual Swift tests and recorded issues; `android/logcat.txt` contains Android runtime diagnostics. The single JUnit wrapper failure alone does not identify which Swift test failed. If the job fails before the emulator test step starts, use the workflow step's build/setup log instead.

After editing Swift-authored Media3 code, clean that generated module before rebuilding if Kotlin's incremental cache retains stale internal visibility metadata. Do not patch generated Kotlin or Gradle output to fix a Swift source problem.

## Known color limitation

A separate diagnostic on candidate `7947b27` confirms a synthetic BT.709 color shift with stable Media3 1.11.1. This affects the stable candidate as well as the preview branch. The API 34 arm64 emulator used SwiftShader and exported one second at 1280x720 through the documented Kotlin wrapper. The source was the [320x180 tagged BT.709 fixture](https://github.com/shial4/SwiftVideo/blob/c9577c1f6f75434576aac28810ada1d8fc10f78c/Tests/SwiftVideoTests/Resources/Milestone/bt709.mp4), SHA-256 `60afd7ee563ab14f0497e2898efa2da4242f7972a51535b866761e3223478b5c`.

| Inspection at 0.5 seconds | Source red / blue channel | Export red / blue channel |
| --- | --- | --- |
| Android MediaMetadataRetriever | 255 / 255 | 231 / 239 |
| Independent Apple sRGB decode | 252 / 252 | 232 / 240 |

The independent decode confirms a difference in the exported file, not only in one inspection API. A first-frame comparison of the bundled coastal example also showed RGB differences in both iOS Simulator and Android emulator exports; that comparison includes scaling and encoding differences and is not a perceptual-visibility score. The coastal source is generated artwork animated into video, as recorded in the [asset provenance](../Example/ASSETS.md).

On November 9, 2026, the maintainer accepted these measured SDR color differences as a documented limitation for 0.0.2. They do not block this release. The measurements do not establish visibility across ordinary footage or scope on physical devices. General export tests passing does not prove color fidelity. See the [bounded release exception](ReleasePlan.md#known-limitations-and-preview-blockers); existing pixel assertions and coverage thresholds are unchanged.
The alpha's local example build required `-Pkotlin.incremental=false` on the Gradle command after changing SDK versions: incremental compilation had retained stale SkipLib and SkipFoundation metadata. This is a process-scoped rebuild option, not a project setting or dependency source change. The example declares SDK 37 in its own Skip configuration, as described in [preview integration](Integration.md#experimental-android-preview).

## Limits of verification

The recorded iOS and Android runtime results use simulators and emulators. This is the agreed release-verification scope; physical-device checks are follow-up work when hardware becomes available. Hardware codec availability, vendor GPU/driver behavior, thermal limits, memory pressure and sustained export throughput on phones remain unverified. No frame-rate or GPU-utilization performance claim is inferred from line coverage. Manual editor checks complement the tests; there is no automated cross-platform UI coverage percentage.
