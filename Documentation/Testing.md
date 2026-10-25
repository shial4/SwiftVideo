<!-- Copyright 2026 Software Deck Pty Ltd; SPDX-License-Identifier: Apache-2.0 -->
# Tests and coverage

[Documentation index](README.md) | [Public API reference](APIReference.md)

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

Android Media3 exports share the serialized `RenderBehaviorTests` suite so concurrent tests do not compete for the hosted emulator's graphics and codec resources. Core and fixture tests remain parallel.

The hosted Android emulator uses four virtual CPU cores and 6 GB of RAM. Its default 2.5 GB configuration caused system-wide memory pressure and ANRs during 1080p exports. CI keeps the same 1080p composition checks and Media3 timeout as local tests.

Apple has additional renderer-specific failure and text-orientation tests, which explain its higher test count. The orientation test independently checks an asymmetric glyph in decoded output; it reproduced the iOS inversion before the fix and passes on both Apple targets. The Android instrumentation runner appears as one JUnit wrapper; `swt-events.jsonl` records the individual Swift Testing results.

## Coverage scope and gates

CI requires at least 90% iOS source lines, 90% Android shared Swift core lines, and 75% Media3 bridge bytecode lines.

The iOS report includes executable first-party `Sources/SwiftVideo` code for that target, including the Apple renderer. Duplicate Xcode package/product coverage entries are checked and deduplicated.

Android core coverage runs an instrumented native Swift test process without a JVM. `SWIFTVIDEO_CORE_COVERAGE` excludes real Android media tests from this process. The Android renderer facade is excluded from this specific percentage because it needs an initialized Android app/JVM; it is exercised by the separate instrumentation suite. The native core percentage must not be described as coverage of the entire Android backend.

JaCoCo measures the generated Kotlin bytecode for the two Swift-authored `SwiftVideoMedia3` implementation files. It is a separate measurement, not Swift source-line coverage. Dependencies, generated bridge support, fixtures, tools, and the example UI are excluded from the library percentages. The three percentages are not averaged.

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

The complete commands live in [android.yml](../.github/workflows/android.yml). Install Skip 1.9.19 or later with a matching Swift Android toolchain/SDK. The local verification configuration is Swift 6.3.2, NDK r27d, Gradle 9.8.2, and an API 34 arm64 emulator. Hosted CI uses `macos-26-intel` and x86_64 Android binaries because GitHub's Apple Silicon runners do not support nested virtualization. On Apple Silicon development machines, use `--arch aarch64`, an arm64 emulator, and the matching `aarch64-unknown-linux-android28` coverage binary path.

The workflow performs these steps in order:

1. Generate Skip metadata with `SKIP_DYNAMIC_LIBRARIES=1 swift build --build-system native --scratch-path .build-media3 --target SwiftVideoTests`.
2. Build the native `SwiftVideo` library and Swift Testing bundle into the generated module's JNI directories.
3. Run a separate instrumented native Swift core suite and pull its `.profraw` files while the emulator is running.
4. Run `:SwiftVideo:connectedDebugAndroidTest` in an Android app with Media3 and an initialized JVM. [TestAndroid.sh](../Tools/TestAndroid.sh) retains Swift Testing events, logcat, and available JUnit reports even when a test fails, while preserving the failing exit status.
5. Process the core profiles with the matching NDK `llvm-profdata` and `llvm-cov`, generate the Media3 JaCoCo XML report, and enforce both Android coverage gates.
6. Compile and package the example editor APK from the same Swift sources.

Use the NDK LLVM tools matching the Swift Android SDK. A different LLVM version can reject its profile format. On a host with a newer incompatible Apple SDK, select a compatible host SDK using process-scoped `DEVELOPER_DIR` and `SDKROOT`; no global Xcode setting is required.

For a CI instrumentation failure, download the `android-test-results` artifact. `android/swt-events.jsonl` identifies individual Swift tests and recorded issues; `android/logcat.txt` contains Android runtime diagnostics. The single JUnit wrapper failure alone does not identify which Swift test failed. If the job fails before the emulator test step starts, use the workflow step's build/setup log instead.

After editing Swift-authored Media3 code, clean that generated module before rebuilding if Kotlin's incremental cache retains stale internal visibility metadata. Do not patch generated Kotlin or Gradle output to fix a Swift source problem.

## Limits of verification

The recorded Android results use an emulator, not a matrix of physical phones. Hardware codec availability, thermal behavior, memory limits, and sustained export throughput require release-build testing on your target devices. No frame-rate or GPU-utilization performance claim is inferred from line coverage. Manual editor checks complement the tests; there is no automated cross-platform UI coverage percentage.
