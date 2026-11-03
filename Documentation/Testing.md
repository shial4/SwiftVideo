<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Tests and coverage

[Documentation index](README.md) | [Public API reference](APIReference.md)

## 0.1.0-alpha.3 verification

The cache now retains the bounding source range used by each URL and adjusts
preview audio trims without changing the source or original render plan. Its
default disk budget replaces the fixed 64 MiB limit. Playback now waits for the first
rendered-frame callback, and completion waits for Media3 to drain pending video
output. The displayed position remains bounded by the project duration. Surface
callbacks now stop the old player before destruction and preserve playback intent
and the exact paused playhead when the surface or its view is replaced.

Local checks on November 4, 2026 passed all 40 macOS tests, Android bridge/native
library/test APK builds, and the 64-file header check. The final API 33 arm64
instrumentation run completed 55 tests in 217.808 seconds with the same six
known color and legacy paused-seek issues. Short 34 ms and 100 ms clips, all four
gap/trim cases, mixed-media final-frame playback, all 20 audio playback/seek
cases, shared-range byte comparisons, the 362-second cache, source-duration
rejection, quota failure, cancellation, and cleanup checks passed. The unchanged
player failed both short-clip cases with zero captured frames at completion and
one frame after a one-second diagnostic wait; that wait does not change the
assertion. [Media3 coverage](Coverage/0.1.0-alpha.3/android-media3.json) is
1,111 / 1,229 executable lines, 90.40%, above the
75% gate. No tolerance or failing assertion was weakened.

The surface regression captures real rendered frames through the public
SurfaceView adapter. It alternates twelve surface and view replacements during
playback, checks late disposal of an older view, and repeats both replacements
while paused. Before the fix it reproduced the app's `Image is already closed`
frame-processing exception. A later run exposed a 1 ms paused-clock change after
Media3 settled its asynchronous pause. The session now retains its own paused
snapshot instead of resampling that clock. The regression passes in 5.272 seconds,
including repeated pause calls and both paused replacement paths. The mixed-media
test also verifies that replacing a completed surface preserves the final video
frame and completed playhead before replaying from the start.

A disposable build of the consuming Skip Fuse app passed its complete phone
rotation workflow against the surface-callback commit `5ff9a68`. The rendered title and playback
clock survive both rotations, pause and seeking remain usable, and the saved
project remains byte-for-byte unchanged. The app's published dependency pin has
not changed.

[Apple CI for the audio-cache commit](https://github.com/shial4/SwiftVideo/actions/runs/41641865959)
passed 40 host tests, 40 iOS tests, five example-model tests, and the iOS example
build, with 1,147 / 1,205 covered iOS lines (95.19%). The Apple reference test
confirms every sample in the new long-offset fixture. The subsequent transport
change passed [Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/41644916740).
Its [Android build retry](https://github.com/shial4/SwiftVideo/actions/runs/41644916753)
passed, but the runtime step reached its five-minute deadline without a completed
instrumentation result. Captured events include an extractor timeout and the
known reference-color failures. The complete hosted Android gate is still failing.
The surface-callback commit subsequently passed
[Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/41658377164), including
40 host tests, 40 iOS tests, five example-model tests, and the iOS example build.
Its Android build and runtime verification are still in progress.

## 0.1.0-alpha.2 verification

This follow-up preserves single-frame MP4 duration, keeps playback intent during surface replacement, and configures SDR surfaces before attaching the player. Local checks ran on November 3, 2026 with Media3 `1.12.0-alpha02`, compile/target SDK 37, and an API 33 arm64 emulator.

| Check | Observed result |
| --- | --- |
| macOS library and example model | 39 library tests and 5 example tests pass |
| Android bridge and test APK | Builds pass |
| Android instrumentation | 51 tests complete in 140.429 seconds with the same six known failing assertions |
| Media3 bytecode coverage | [992 / 1,143 lines, 86.79%](Coverage/0.1.0-alpha.2/android-media3.json); exceeds the 75% gate |
| Single-frame export | Independently decoded 1/30-second and 1/40-second movies retain duration, size, and pixels |
| Consuming Skip Fuse app | Two complete orientation runs preserve the playback clock, rendered title, pause/seek controls, and saved JSON |

The six local failures remain four BT.709 export-color assertions and two legacy paused-seek assertions. Production preview, gap/source-trim, audio-boundary, surface replacement, and cache checks pass locally. No failing assertion was disabled. The shared Swift core is unchanged from the [alpha.1 coverage measurement](Coverage/0.1.0-alpha.1/android-core.json); that measurement was not repeated for this follow-up.

The [alpha.2 hosted Android run](https://github.com/shial4/SwiftVideo/actions/runs/41632246965) built successfully and completed 51 instrumentation tests in 237.333 seconds with eight issues: the six above plus two short-video preview cases at timeline start zero, with source trims of zero and 250 ms. Both reported zero rendered frames. The 31 native Swift core tests passed. Unlike the earlier [alpha.1 run](https://github.com/shial4/SwiftVideo/actions/runs/41616294181), this run completed without reaching its runtime deadline. These differences from the local emulator remain unresolved. The full Android test gate is still failing. Physical-device and interactive iOS verification remain outstanding, and the published alpha's whole-source preview audio cache still has a cumulative 64 MiB limit. This is an experimental prerelease; stable release gates below still apply.

## 0.1.0-alpha.1 verification

The Media3 `1.12.0-alpha02` candidate was checked on November 3, 2026 with compile/target SDK 37 and an API 33 arm64 emulator.

| Check | Observed result |
| --- | --- |
| macOS library and example model | 39 library tests and 5 example tests pass |
| Android native Swift core | 31 tests pass; [707 / 751 lines, 94.14%](Coverage/0.1.0-alpha.1/android-core.json) |
| Android instrumentation | 50 tests complete in 209.79 seconds with six known failing assertions |
| Media3 bytecode coverage | [993 / 1,136 lines, 87.41%](Coverage/0.1.0-alpha.1/android-media3.json) |
| Android bridge, native library, test APK | Builds pass |
| Android example consumer | Native build, APK packaging, and launch pass; packaged compile/target SDK 37, minimum API 28 |
| Generic iOS example | Build passes |

Both measured Android coverage thresholds pass. The complete Android test gate remains failing because of the assertions below; coverage does not make that suite green. These local results do not establish a passing release CI run.

The 50-test Android diagnostic run recorded six issues: four BT.709 export-color assertions and two legacy paused-seek control assertions. Those assertions remain enabled. The production preview checks passed mixed-media playback, all four gap/source-trim cases, animation, rapid seeking, surface replacement, and 16 audio trim/seek cases. Cache tests passed source onset, exact sample counts, reuse, quota enforcement, cancellation, and release cleanup. See [fixture provenance and diagnostics](../Tests/SwiftVideoTests/Resources/Milestone/README.md).

The direct preview is experimental and is not integrated into the example editor. Its whole-source PCM cache has a cumulative 64 MiB limit. Physical-device behavior is unverified. Interactive iOS tests are currently unavailable locally because the installed CoreSimulator framework does not match Xcode; a generic build does not replace those tests. A stable release requires stable dependencies and verification of its final commit against the gates below.

## 0.0.1 verification snapshot

The 0.0.1 verification snapshot was measured on October 25, 2026. Coverage reports contain executable-line counts, not estimates.

| Target | Observed result | Coverage |
| --- | --- | --- |
| macOS library | 36 tests, 6 suites passed | Integration and core behavior |
| iOS 26.5 Simulator | 36 tests, 6 suites passed | 1,128 / 1,186 lines, 95.11% |
| Android API 34 arm64 instrumentation | 35 tests, 6 suites passed | Real Media3 exports and native Swift tests |
| Android native Swift core | 30 tests, 4 suites passed | 688 / 726 lines, 94.77% |
| Android Media3 bridge | Instrumentation coverage | 326 / 362 generated lines, 90.06% |
| Example editor model on macOS | 5 tests passed | Asset loading, edits, history, selection, failure handling |

See the checked-in [iOS](Coverage/ios.json), [Android core](Coverage/android-core.json), and [Media3](Coverage/android-media3.json) reports. These are release snapshots. GitHub Actions uploads reports for each run; README workflow badges link to the current result.

Manual editor checks covered macOS, iOS Simulator, and Android Emulator. The final Android example export was independently decoded as an 8-second, 1920x1080, 30 fps MP4 with audio; inspected frames confirmed the image/title scene and captioned picture-in-picture scene.

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

CI compiles Android binaries on macOS and runs them on an Ubuntu KVM emulator with two virtual CPU cores and 4 GB of RAM. Emulator 36.6.11 is pinned to match the version used for local verification. CI uses the same composition tests and Media3 timeout as local tests. The device-test command has a five-minute deadline so an unresponsive emulator cannot hold the job indefinitely.

Apple has additional renderer-specific failure and text-orientation tests, which explain its higher test count. The orientation test independently checks an asymmetric glyph in decoded output; it reproduced the iOS inversion before the fix and passes on both Apple targets. The Android instrumentation runner appears as one JUnit wrapper; `swt-events.jsonl` records the individual Swift Testing results.

## Coverage scope and gates

CI requires at least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines.

The iOS report includes executable first-party `Sources/SwiftVideo` code for that target, including the Apple renderer. Duplicate Xcode package/product coverage entries are checked and deduplicated.

Android core coverage runs an instrumented native Swift test process without a JVM. `SWIFTVIDEO_CORE_COVERAGE` excludes real Android media tests from this process. The Android renderer facade is excluded from this specific percentage because it needs an initialized Android app/JVM; it is exercised by the separate instrumentation suite. The native core percentage must not be described as coverage of the entire Android backend.

JaCoCo measures the generated Kotlin bytecode for the Swift-authored `SwiftVideoMedia3` implementation. It is a separate measurement, not Swift source-line coverage. Dependencies, generated bridge support, fixtures, tools, and the example UI are excluded from the library percentages. The three percentages are not averaged.

## Reproduce Apple tests

From the repository root:

```sh
swift test --disable-xctest --enable-code-coverage
swift test --package-path Example --disable-xctest
swift Tools/CheckHeaders.swift
```

For iOS, use the `xcodebuild` command in [apple.yml](../.github/workflows/apple.yml), selecting an installed simulator. It selects the six Swift Testing suites explicitly, writes an `.xcresult`, exports `xccov` JSON, and checks coverage with `Tools/Coverage.swift`.

Local verification used Xcode 27.1, the iOS 26.5 Simulator, and macOS 26.6. CI selects Xcode 26.6 on `macos-26`. Apple video tests require a Metal-capable rendering environment.

## Reproduce Android tests

The complete commands live in [android.yml](../.github/workflows/android.yml). Use an existing Skip installation with a matching Swift Android toolchain/SDK. The local verification configuration is Swift 6.3.2, NDK r27d, Gradle 9.8.2, and an API 34 arm64 emulator. Hosted CI cross-compiles x86_64 Android binaries on `macos-26-intel`, then transfers them to `ubuntu-24.04` for execution. Xcode's compiler builds host metadata, including the Apple AVKit preview; Swift 6.3.2 builds Android binaries. The emulator runner needs only ADB and the packaged binaries; it does not install Swift. On Apple Silicon development machines, use `--arch aarch64` for native builds, `ANDROID_ARCH=aarch64` when packaging, and an arm64 emulator.

The workflow performs these steps in order:

1. Generate Skip metadata with `SKIP_DYNAMIC_LIBRARIES=1 xcrun swift build --build-system native --scratch-path .build-media3 --target SwiftVideoTests`.
2. Build the native `SwiftVideo` library and Swift Testing bundle into the generated module's JNI directories.
3. [BuildAndroidTests.sh](../Tools/BuildAndroidTests.sh) builds the instrumented native core executable, runtime libraries, and Media3 test APK, and packages their matching coverage metadata. The macOS job also compiles the example editor APK.
4. On the emulator host, [TestAndroid.sh](../Tools/TestAndroid.sh) runs the core executable and Android instrumentation APK, pulls native profiles and JaCoCo data, and retains Swift Testing events and logcat even when a test fails. It checks the JUnit result explicitly because Android's instrumentation command can exit zero after test failures.
5. Process the core profiles with the matching NDK `llvm-profdata` and `llvm-cov`, generate the Media3 JaCoCo XML report, and enforce both Android coverage gates.

For local use after generating metadata and building the JNI libraries, set `ANDROID_MODULE` to the generated `SwiftVideo` Gradle module and `SWIFT_VERSION` to the installed version. Run `bash Tools/BuildAndroidTests.sh`, then `bash Tools/TestAndroid.sh` with an emulator connected. Both scripts accept `ANDROID_TEST_ARTIFACTS` to override the default `.build-android-tests` directory. Standard `ANDROID_SERIAL` selects a specific connected device.

Use the NDK LLVM tools matching the Swift Android SDK. A different LLVM version can reject its profile format. On a host with a newer incompatible Apple SDK, select a compatible host SDK using process-scoped `DEVELOPER_DIR` and `SDKROOT`; no global Xcode setting is required.

For a CI instrumentation failure, download the `android-test-results` artifact. `android/swt-events.jsonl` identifies individual Swift tests and recorded issues; `android/logcat.txt` contains Android runtime diagnostics. The single JUnit wrapper failure alone does not identify which Swift test failed. If the job fails before the emulator test step starts, use the workflow step's build/setup log instead.

After editing Swift-authored Media3 code, clean that generated module before rebuilding if Kotlin's incremental cache retains stale internal visibility metadata. Do not patch generated Kotlin or Gradle output to fix a Swift source problem.

The alpha's local example build required `-Pkotlin.incremental=false` on the Gradle command after changing SDK versions: incremental compilation had retained stale SkipLib and SkipFoundation metadata. This is a process-scoped rebuild option, not a project setting or dependency source change. The example declares SDK 37 in its own Skip configuration, as described in [preview integration](Integration.md#experimental-android-preview).

## Limits of verification

The recorded Android results use an emulator, not a matrix of physical phones. Hardware codec availability, thermal behavior, memory limits, and sustained export throughput require release-build testing on your target devices. No frame-rate or GPU-utilization performance claim is inferred from line coverage. Manual editor checks complement the tests; there is no automated cross-platform UI coverage percentage.
