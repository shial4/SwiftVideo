#!/usr/bin/env bash
# Copyright 2026 Software Deck Pty Ltd
# SPDX-License-Identifier: Apache-2.0

# Run inside an already-booted emulator. Keep diagnostics even when Gradle fails.
set -euo pipefail

: "${ANDROID_MODULE:?Set ANDROID_MODULE to the generated SwiftVideo Gradle module.}"
: "${SWIFT_VERSION:?Set SWIFT_VERSION to the installed Android Swift version.}"
android_arch="${ANDROID_ARCH:-x86_64}"
reports="$PWD/.build-coverage/android"
mkdir -p "$reports"

collect_results() {
    local test_status=$?
    trap - EXIT
    adb logcat -d -v raw -s SwiftTest:I > "$reports/swt-events.jsonl" || true
    adb logcat -d -v threadtime > "$reports/logcat.txt" || true
    for directory in outputs/androidTest-results reports/androidTests; do
        if [[ -d "$ANDROID_MODULE/build/$directory" ]]; then
            cp -R "$ANDROID_MODULE/build/$directory" "$reports/" || true
        fi
    done
    if [[ "$test_status" -ne 0 ]]; then
        printf '%s\n' 'Swift Testing events from the failed Android test run:'
        cat "$reports/swt-events.jsonl"
    fi
    exit "$test_status"
}
trap collect_results EXIT

skip android test --swift-version "$SWIFT_VERSION" --arch "$android_arch" \
    --scratch-path .build-android-coverage --testing-library testing --no-cleanup \
    --remote-folder /data/local/tmp/swiftvideo-coverage \
    --env 'LLVM_PROFILE_FILE=/data/local/tmp/swiftvideo-coverage/coverage-%m.profraw' \
    -Xswiftc -DSWIFTVIDEO_CORE_COVERAGE -Xswiftc -profile-generate -Xswiftc -profile-coverage-mapping

# Pull native coverage before instrumentation so a later failure cannot lose it.
adb shell 'cd /data/local/tmp/swiftvideo-coverage && tar -cf /data/local/tmp/swiftvideo-profiles.tar coverage-*.profraw'
adb pull /data/local/tmp/swiftvideo-profiles.tar "$reports/profiles.tar"

# Direct Gradle output makes compilation and device-test progress visible in CI.
SKIP_BRIDGE_ANDROID_BUILD_DISABLED=1 gradle --console=plain -p "$ANDROID_MODULE/.." \
    :SwiftVideo:connectedDebugAndroidTest
