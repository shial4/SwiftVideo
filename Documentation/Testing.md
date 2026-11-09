<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Tests and coverage

[Documentation index](README.md) | [Public API reference](APIReference.md)

## Stable adoption gate

November 10 follow-up: the shared offline-audio initialization and unwritten-muxer cancellation fixes are backported in `07924bf`. A further bounded PCM-preparation fix normalizes fractional source trims before Android export. The new regression reproduced silent starts and delayed fades on the stable beta.3 implementation, and an independent Media3 1.11.1 control reproduced variable input offsets. The fix copies only the selected PCM range off the application looper and preserves cancellation cleanup.

With that fix, the API 35 arm64 preview run executed 75 test functions in eight suites in 185.492 seconds. All audio checks passed, including the existing 20 trim/seek cases, retimed preview/export comparisons, 12 new PCM16/float exports and cancellation/failure recovery. The full run still failed with six issues: four measured color differences and two missing green-overlay frames in raw CompositionPlayer seek/reset controls. Existing thresholds are unchanged; this is not a passing Android release gate. The supported recreation path passed in this run, but dependency and remaining preview gates still apply.

Before the PCM-only Android change, the shared backports passed 56 macOS and 56 iOS test functions; iOS coverage was 1,574/1,649 (95.45%). Final-head hosted checks remain required. Earlier alpha tags are unchanged.

PR #1 includes `main` through `d2977a2`; its documentation conflicts are resolved.
Local verification on November 6, 2026 passes all 56 macOS library tests, 56 iOS
library tests on iOS 27, and six editor model tests. The iOS LLVM report measures
1,570/1,645 executable source lines (95.44%). All 40 native Android core tests
also pass, with 979/1,053 source lines covered (92.97%). These local results do
not establish a passing hosted or Media3 instrumentation release gate.

Stable adoption still requires passing Apple and Android CI, all three coverage
gates, and a stable Media3 dependency that supports the preview implementation.
A version-number change alone does not meet that requirement:

- Google's [release index](https://developer.android.com/jetpack/androidx/releases/media3)
  lists 1.11.1 as stable; 1.12.0-alpha02 remains a prerelease.
- Building this branch against 1.11.1 fails because
  `DefaultGlFrameProcessor.Factory.Builder` is unavailable. Its
  [older factory](https://github.com/androidx/media/blob/1.11.1/libraries/effect/src/main/java/androidx/media3/effect/DefaultGlFrameProcessor.java)
  requires caller-owned GL resources and a `HardwareBufferJniWrapper`.
- The matching [native helper implementation](https://github.com/androidx/media/blob/1.11.1/libraries/effect_ndk/src/main/java/androidx/media3/effect/ndk/HardwareBufferJni.java)
  is in the upstream source tree, but Google's
  [Maven artifact index](https://dl.google.com/dl/android/maven2/androidx/media3/group-index.xml)
  does not publish that NDK module. Both candidate 1.11.1 artifact coordinates
  (`media3-effect-ndk` and `lib-effect-ndk`) return 404.

The dependency therefore remains 1.12.0-alpha02. Adopt a compatible stable
upstream release and rerun the complete gates before merging. The independent
BT.709 color and paused-seek assertions remain enabled with their original
tolerances; the previous failing Android runs are not release passes.

## Latest complete coverage snapshot: 0.1.0-alpha.5

This alpha adds clip and track speed, ordered visual filter inheritance, audio
EQ, and example editor controls. Preview and export share the same resolved
rates and filter order. Preview audio caching and seek boundaries use source
time; fades and animations retain their project-time clocks.

Local verification on November 5, 2026 passes all 51 macOS library tests, 51 iOS
library tests on an iOS 27 simulator, 39 native Android core tests on API 34 arm64,
and six example editor model tests. Android bridge/native compilation, both example app builds, all 71 source
headers, local documentation links, and whitespace checks pass.

Measured [iOS coverage](Coverage/ios.json) is 1,499/1,570 executable
lines (95.48%); [Android core coverage](Coverage/android-core.json)
is 955/1,000 (95.50%). Both exceed their unchanged 90% gates. The iOS report uses
the direct LLVM export of the passing test binary and its profile because the
Xcode `xccov` summary again omitted first-party sources.

The final API 34 arm64 instrumentation run completed 67 tests in six suites in
382.399 seconds with seven failing assertions: four BT.709 export-color checks,
two legacy paused-seek checks, and the direct frame-processor paused-seek
control. The latter passed in the first run and failed in the next two; the
production session uses player recreation. Production preview, surface/view
replacement, all 20 audio trim/seek cases, four pitch-preserving speed cases,
ordered EQ, and both retimed preview/seek cases pass in the final run.

One preceding run also reported a 0.022 RMS difference between 0.5x preview and
export, both before and after seeking. The final run passed those same checks
without changing their 0.01 tolerance or the audio implementation. This
intermittent result remains unresolved; the passing rerun does not establish
that the issue is fixed. No failing assertion was disabled or relaxed.

Measured [Media3 coverage](Coverage/android-media3.json) is
1,190/1,310 executable lines (90.84%), above the unchanged 75% gate. Coverage
measures executed code even when assertions fail; it does not establish a
passing Android gate. Hosted CI at the alpha release commit and physical-device
behavior remain unverified. This is an experimental prerelease.

## Earlier verification records

Historical test reports and diagnostics live at their release tags. The current
branch keeps only the three compact coverage summaries used by the README.
Raw profiles, logs, and test bundles belong in local build folders or CI artifacts.

| Release | Verification record |
| --- | --- |
| 0.1.0-alpha.6 | [Layer preview checks and limitations](https://github.com/shial4/SwiftVideo/releases/tag/0.1.0-alpha.6) |
| 0.1.0-alpha.4 | [Hosted fonts, frame inspection, and seek controls](https://github.com/shial4/SwiftVideo/blob/0.1.0-alpha.4/Documentation/Testing.md) |
| 0.1.0-alpha.3 | [Preview caching, audio boundaries, surface lifecycle, and hosted CI](https://github.com/shial4/SwiftVideo/blob/0.1.0-alpha.3/Documentation/Testing.md) |
| 0.1.0-alpha.2 | [Single-frame export and preview follow-up](https://github.com/shial4/SwiftVideo/blob/0.1.0-alpha.2/Documentation/Testing.md) |
| 0.1.0-alpha.1 | [Initial experimental preview verification](https://github.com/shial4/SwiftVideo/blob/0.1.0-alpha.1/Documentation/Testing.md) |
| 0.0.1 | [Original stable verification snapshot](https://github.com/shial4/SwiftVideo/blob/0.0.1/Documentation/Testing.md) |

## What the tests verify

- Rational frame/time arithmetic, overflow, input validation, and JSON round trips.
- Builder loops, branches, reusable arrays, thrown errors, stable IDs, immutable modifiers, and bounded text allocation.
- Atomic edits, missing targets, failed-batch rollback, split/trim source ranges, animation continuity, and audio envelopes.
- Export progress, cancellation, cleanup after failure, unsupported capabilities, and protection of existing destinations.
- Independently decoded real exports: duration, dimensions, frame changes, filters, crop, stacking, image opacity, text/animation, audio energy, stereo pan, and fades.
- Android fixture copies have independent file contents, so parallel tests cannot overwrite media another test is decoding.

The media fixtures are deterministic red/blue videos, a green image, and synthesized audio. Pixel and PCM measurements use platform decoders independently of the compositor. Tests allow codec/color conversion tolerances; they do not compare byte-identical compressed files across platforms.

Android Media3 rendering and source-frame decoding share the serialized `RenderBehaviorTests` suite so concurrent tests do not compete for the hosted emulator's graphics and codec resources. Core and fixture file-copy tests remain parallel.

Routine composition tests on both platforms render at 320x180. They verify decoded pixels, overlay placement, relative text motion, timing, and audio fades with much less rendering work than a full HD export. The separate manual example checks cover 1080p output.

CI compiles Android binaries on macOS and runs them on an Ubuntu KVM emulator with two virtual CPU cores and 4 GB of RAM. Emulator 36.6.11 is pinned to match the version used for local verification. CI uses the same composition tests and Media3 timeout as local tests. The complete device-test command has a fifteen-minute deadline, with thirty seconds to collect diagnostics before forced termination. Individual test assertions and timeouts are unchanged.

Apple has additional renderer-specific failure and text-orientation tests, which explain its higher test count. The orientation test independently checks an asymmetric glyph in decoded output; it reproduced the iOS inversion before the fix and passes on both Apple targets. The Android instrumentation runner appears as one JUnit wrapper; `swt-events.jsonl` records the individual Swift Testing results.

## Coverage scope and gates

CI requires at least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines.

The iOS report includes executable first-party `Sources/SwiftVideo` code for that target, including the Apple renderer. Duplicate Xcode package/product coverage entries are checked and deduplicated.

Android core coverage runs an instrumented native Swift test process without a JVM. `SWIFTVIDEO_CORE_COVERAGE` excludes real Android media tests from this process. The Android renderer facade is excluded from this specific percentage because it needs an initialized Android app/JVM; it is exercised by the separate instrumentation suite. The native core percentage must not be described as coverage of the entire Android backend.

JaCoCo measures the generated Kotlin bytecode for the Swift-authored `SwiftVideoMedia3` implementation. It is a separate measurement, not Swift source-line coverage. Dependencies, generated bridge support, fixtures, tools, and the example UI are excluded from the library percentages. The three percentages are not averaged.

## Reproduce Apple tests

From the repository root:

```sh
swift test --build-system native --disable-xctest --enable-code-coverage
swift test --build-system native --package-path Example --disable-xctest
swift Tools/CheckHeaders.swift
```

For iOS, use the `xcodebuild` command in [apple.yml](../.github/workflows/apple.yml), selecting an installed simulator. It runs every applicable test suite, including layer rendering, and writes an `.xcresult`.

[CollectIOSCoverage.sh](../Tools/CollectIOSCoverage.sh) requires a passing,
nonempty test result. It selects the simulator profiles identified by that
result bundle and exports the matching test binary's LLVM coverage mapping.
This avoids Xcode summaries that omit Swift package source files. The existing
`Tools/Coverage.swift` source scope and 90% gate are unchanged.

```sh
bash Tools/CollectIOSCoverage.sh .build-coverage/iOS.xcresult .build-ios .build-coverage
```

CI selects Xcode 26.6 on `macos-26`. Apple video tests require a Metal-capable
rendering environment. Host tests use the native SwiftPM build system with
unbuffered output. If the host step stalls, CI retains process samples before
its twelve-minute deadline; a timeout remains a failed check.

## Reproduce Android tests

The complete commands live in [android.yml](../.github/workflows/android.yml). Use an existing Skip installation with a matching Swift Android toolchain/SDK. The local verification configuration is Swift 6.3.2, NDK r27d, Gradle 9.8.2, and an API 34 arm64 emulator. Hosted CI cross-compiles x86_64 Android binaries on `macos-26-intel`, then transfers them to `ubuntu-24.04` for execution. Xcode's compiler builds host metadata, including the Apple AVKit preview; Swift 6.3.2 builds Android binaries. The emulator runner needs only ADB and the packaged binaries; it does not install Swift. On Apple Silicon development machines, use `--arch aarch64` for native builds, `ANDROID_ARCH=aarch64` when packaging, and an arm64 emulator.

The workflow has three jobs: `build` packages the test binaries, `tests` runs after `build`, and `example` builds the editor independently. The example no longer delays the emulator tests. Both macOS jobs use the same [setup action](../.github/actions/setup-android/action.yml), which caches the pinned toolchains and SwiftPM downloads. Gradle manages its dependency and task caches; cache writes are also enabled for same-repository PRs and the alpha branch. Generated Skip bridges and native incremental build directories are rebuilt from source. Toolchain caches have exact version/setup keys; SwiftPM caches are separated by build job and dependency manifests.

The test jobs perform these steps in order:

1. Generate Skip metadata with `SKIP_DYNAMIC_LIBRARIES=1 xcrun swift build --build-system native --scratch-path .build-media3 --target SwiftVideoTests`.
2. Build the native `SwiftVideo` library and Swift Testing bundle into the generated module's JNI directories.
3. [BuildAndroidTests.sh](../Tools/BuildAndroidTests.sh) builds the instrumented native core executable, runtime libraries, and Media3 test APK, and packages their matching coverage metadata.
4. On the emulator host, [TestAndroid.sh](../Tools/TestAndroid.sh) runs the core executable and Android instrumentation APK, pulls native profiles and JaCoCo data, and retains Swift Testing events and logcat even when a test fails. It checks the JUnit result explicitly because Android's instrumentation command can exit zero after test failures.
5. Process the core profiles with the matching NDK `llvm-profdata` and `llvm-cov`, generate the Media3 JaCoCo XML report, and enforce both Android coverage gates.

For local use after generating metadata and building the JNI libraries, set `ANDROID_MODULE` to the generated `SwiftVideo` Gradle module and `SWIFT_VERSION` to the installed version. Run `bash Tools/BuildAndroidTests.sh`, then `bash Tools/TestAndroid.sh` with an emulator connected. Both scripts accept `ANDROID_TEST_ARTIFACTS` to override the default `.build-android-tests` directory. Standard `ANDROID_SERIAL` selects a specific connected device.

Use the NDK LLVM tools matching the Swift Android SDK. A different LLVM version can reject its profile format. On a host with a newer incompatible Apple SDK, select a compatible host SDK using process-scoped `DEVELOPER_DIR` and `SDKROOT`; no global Xcode setting is required.

For a CI instrumentation failure, download the `android-test-results` artifact. `android/swt-events.jsonl` identifies individual Swift tests and recorded issues; `android/logcat.txt` contains Android runtime diagnostics. The single JUnit wrapper failure alone does not identify which Swift test failed. If the job fails before the emulator test step starts, use the workflow step's build/setup log instead.

After editing Swift-authored Media3 code, clean that generated module before rebuilding if Kotlin's incremental cache retains stale internal visibility metadata. Do not patch generated Kotlin or Gradle output to fix a Swift source problem.

The alpha's local example build required `-Pkotlin.incremental=false` on the Gradle command after changing SDK versions: incremental compilation had retained stale SkipLib and SkipFoundation metadata. This is a process-scoped rebuild option, not a project setting or dependency source change. The example declares SDK 37 in its own Skip configuration, as described in [preview integration](Integration.md#experimental-android-preview).

## Limits of verification

The recorded Android results use an emulator, not a matrix of physical phones. Hardware codec availability, thermal behavior, memory limits, and sustained export throughput require release-build testing on your target devices. No frame-rate or GPU-utilization performance claim is inferred from line coverage. Manual editor checks complement the tests; there is no automated cross-platform UI coverage percentage.
