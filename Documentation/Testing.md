<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Tests and coverage

[Documentation index](README.md) | [Public API reference](APIReference.md)

The local verification snapshot for [0.0.2 stabilization](ReleasePlan.md) was measured on November 9, 2026. The 0.0.1 tag predates the playback speed and ordered filter APIs. Coverage reports contain executable-line counts, not estimates. Release verification uses iOS Simulator and Android emulators; physical-device access is not a prerequisite. Beta observation remains a separate release gate.

| Target | Observed result | Coverage |
| --- | --- | --- |
| macOS library | 44 tests, 6 suites passed | Integration and core behavior |
| iOS 27.0 Simulator | 44 tests, 6 suites passed | 1,467 / 1,538 lines, 95.38% |
| Android API 34 and API 35 arm64 instrumentation | 43 tests, 6 suites passed on each | Real Media3 exports and native Swift tests |
| Android native Swift core | 35 tests, 4 suites passed | 921 / 960 lines, 95.94% |
| Android Media3 bridge | API 34 instrumentation coverage | 404 / 442 generated lines, 91.40% |
| Example editor model on macOS | 6 tests passed | Asset loading, edits, history, selection, failure handling |

See the checked-in [iOS](Coverage/ios.json), [Android core](Coverage/android-core.json), and [Media3](Coverage/android-media3.json) reports. These are verification snapshots for the documented revision. GitHub Actions uploads reports for each run; README workflow badges link to the current result.

Candidate `7947b27` also passed [hosted Apple CI](https://github.com/shial4/SwiftVideo/actions/runs/42527055392) and [hosted Android CI](https://github.com/shial4/SwiftVideo/actions/runs/42527055454), including all three coverage gates and the example builds. A standalone SwiftPM consumer exported a title with combined clip/track speed and filters. The documented Kotlin wrapper was packaged into AARs and invoked from a standalone native Kotlin consumer on API 34; export/decode and missing-input cleanup checks passed. An unsigned Release build for physical iPhones also compiled, but has not been run on hardware.

The November 9 example builds pass for iOS Simulator and Android, with six editor model tests passing on macOS. The original 0.0.1 manual editor checks covered macOS, iOS Simulator, and Android Emulator. That release's Android example export was independently decoded as an 8-second, 1920x1080, 30 fps MP4 with audio; inspected frames confirmed the image/title scene and captioned picture-in-picture scene.

## What the tests verify

- Rational frame/time arithmetic, clip/track speed multiplication, retimed gaps, overflow, input validation, and backward-compatible JSON decoding.
- Pitch preservation from 0.25x through 4x, selected source ranges, leading/trailing audio, and low-pass/high-pass/parametric EQ attenuation.
- Clip-before-track filter inheritance, failed track replacement rollback, and editor speed/filter undo and redo.
- Builder loops, branches, reusable arrays, thrown errors, stable IDs, immutable modifiers, and bounded text allocation.
- Atomic edits, missing targets, failed-batch rollback, split/trim source ranges, animation continuity, and audio envelopes.
- Export progress, cancellation, cleanup after failure, unsupported capabilities, and protection of existing destinations.
- Independently decoded real exports: duration, dimensions, frame changes, filters, crop, stacking, image opacity, text/animation, audio energy, stereo pan, and fades.
- One-frame Android MP4 exports retain their requested 25 ms or 33.33 ms duration and decode the expected image. The regression test reproduced zero-duration output before the muxer endpoint fix.
- Android fixture copies have independent file contents, so parallel tests cannot overwrite media another test is decoding.

The media fixtures are deterministic red/blue videos, a green image, and synthesized audio. Pixel and PCM measurements use platform decoders independently of the compositor. Tests allow codec/color conversion tolerances; they do not compare byte-identical compressed files across platforms.

Android Media3 exports share the serialized `RenderBehaviorTests` suite so concurrent tests do not compete for the hosted emulator's graphics and codec resources. Core and fixture tests remain parallel.

Routine composition tests on both platforms render at 320x180. They verify decoded pixels, overlay placement, relative text motion, timing, and audio fades with much less rendering work than a full HD export. The separate manual example checks cover 1080p output.

CI compiles Android binaries on macOS and runs them on an Ubuntu KVM emulator with two virtual CPU cores and 4 GB of RAM. Emulator 36.6.11 is pinned to match the version used for local verification. CI uses the same composition tests and Media3 timeout as local tests. The device-test command has a five-minute deadline so an unresponsive emulator cannot hold the job indefinitely.

Apple has additional renderer-specific failure and text-orientation tests, which explain its higher test count. The orientation test independently checks an asymmetric glyph in decoded output; it reproduced the iOS inversion before the fix and passes on both Apple targets. The Android instrumentation runner appears as one JUnit wrapper; `swt-events.jsonl` records the individual Swift Testing results.

## Coverage scope and gates

CI requires at least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines.

The iOS report includes executable first-party `Sources/SwiftVideo` code for that target, including the Apple renderer. The collector uses the tested binary's LLVM mapping and profiles for the result bundle's devices, because Xcode's `xccov` summary can omit package sources. The report parser also accepts `xccov` input and checks duplicate package/product entries for consistency.

Android core coverage runs an instrumented native Swift test process without a JVM. `SWIFTVIDEO_CORE_COVERAGE` excludes real Android media tests from this process. The Android renderer facade is excluded from this specific percentage because it needs an initialized Android app/JVM; it is exercised by the separate instrumentation suite. The native core percentage must not be described as coverage of the entire Android backend.

JaCoCo measures the generated Kotlin bytecode for the Swift-authored `SwiftVideoMedia3` implementation files. It is a separate measurement, not Swift source-line coverage. Dependencies, generated bridge support, fixtures, tools, and the example UI are excluded from the library percentages. The three percentages are not averaged.

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

The workflow performs these steps in order:

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

The independent decode confirms a difference in the exported file, not only in one inspection API. These measurements do not establish how noticeable it is in ordinary footage or its scope on physical devices. General export tests passing does not prove color fidelity. The [release plan](ReleasePlan.md#known-limitations-and-preview-blockers) tracks acceptance of this bounded limitation separately; existing pixel assertions and coverage thresholds are unchanged.

## Limits of verification

The recorded iOS and Android runtime results use simulators and emulators. This is the agreed release-verification scope; physical-device checks are follow-up work when hardware becomes available. Hardware codec availability, vendor GPU/driver behavior, thermal limits, memory pressure and sustained export throughput on phones remain unverified. No frame-rate or GPU-utilization performance claim is inferred from line coverage. Manual editor checks complement the tests; there is no automated cross-platform UI coverage percentage.
