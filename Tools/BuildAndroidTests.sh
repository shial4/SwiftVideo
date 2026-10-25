#!/usr/bin/env bash
# Copyright 2026 Software Deck Pty Ltd
# SPDX-License-Identifier: Apache-2.0

# Package native core tests, the Media3 test APK, and matching coverage metadata.
set -euo pipefail

: "${ANDROID_MODULE:?Set ANDROID_MODULE to the generated SwiftVideo Gradle module.}"
: "${SWIFT_VERSION:?Set SWIFT_VERSION to the installed Android Swift version.}"
android_arch="${ANDROID_ARCH:-x86_64}"
case "$android_arch" in
    x86_64) abi=x86_64 ;;
    aarch64) abi=arm64-v8a ;;
    *) printf 'Unsupported test architecture: %s\n' "$android_arch" >&2; exit 2 ;;
esac
artifacts="${ANDROID_TEST_ARTIFACTS:-$PWD/.build-android-tests}"
mkdir -p "$artifacts/core" "$artifacts/media3"

skip android build --swift-version "$SWIFT_VERSION" --arch "$android_arch" \
    --scratch-path .build-android-coverage --no-prune --dir "$artifacts/native" \
    -Xswiftc -DSWIFTVIDEO_CORE_COVERAGE -Xswiftc -profile-generate \
    -Xswiftc -profile-coverage-mapping --build-tests
cp "$artifacts/native/$abi/"*.so "$artifacts/core/"
core_build=".build-android-coverage/$android_arch-unknown-linux-android28/debug"
executables=("$core_build/"*PackageTests.xctest)
test "${#executables[@]}" -eq 1
cp "${executables[0]}" "$artifacts/core/tests.xctest"
cp -R "$core_build/"*.resources "$artifacts/core/"

SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 gradle --console=plain -p "$ANDROID_MODULE/.." \
    :SwiftVideo:assembleDebugAndroidTest
cp "$ANDROID_MODULE/build/outputs/apk/androidTest/debug/SwiftVideo-debug-androidTest.apk" "$artifacts/tests.apk"
cp -R "$ANDROID_MODULE/../SwiftVideoMedia3/build/intermediates/built_in_kotlinc/debug/compileDebugKotlin/classes" "$artifacts/media3/"
cp -R "$ANDROID_MODULE/../SwiftVideoMedia3/src/main/kotlin" "$artifacts/media3/"
