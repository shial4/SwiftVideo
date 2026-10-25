#!/usr/bin/env bash
# Copyright 2026 Software Deck Pty Ltd
# SPDX-License-Identifier: Apache-2.0

# Run prebuilt tests on an already-booted emulator. No host Swift SDK is needed.
set -euo pipefail

artifacts="${ANDROID_TEST_ARTIFACTS:-$PWD/.build-android-tests}"
reports="$PWD/.build-coverage/android"
mkdir -p "$reports"

collect_results() {
    local test_status=$?
    trap - EXIT
    adb logcat -d -v raw -s SwiftTest:I > "$reports/swt-events.jsonl" || true
    adb logcat -d -v threadtime > "$reports/logcat.txt" || true
    if [[ "$test_status" -ne 0 ]]; then
        printf '%s\n' 'Swift Testing events from the failed Android test run:'
        cat "$reports/swt-events.jsonl"
    fi
    exit "$test_status"
}
trap collect_results EXIT
trap 'exit 124' TERM

remote=$(adb shell mktemp -d /data/local/tmp/swiftvideo-tests.XXXXXX | tr -d '\r')
adb push "$artifacts/core/." "$remote/"
adb shell "cd '$remote' && chmod +x tests.xctest && LD_LIBRARY_PATH=. LLVM_PROFILE_FILE=coverage-%m.profraw ./tests.xctest --testing-library swift-testing" \
    | tee "$reports/core-tests.txt"

# Pull native coverage before instrumentation so a later failure cannot lose it.
adb shell "cd '$remote' && tar -cf profiles.tar coverage-*.profraw"
adb pull "$remote/profiles.tar" "$reports/profiles.tar"

adb shell cat /proc/meminfo > "$reports/meminfo-before-instrumentation.txt" || true
adb install -r -t "$artifacts/tests.apk"
adb logcat -c
adb shell am instrument -w -e coverage true \
    -e coverageFile /data/user/0/swift.video.module.test/coverage.ec \
    swift.video.module.test/androidx.test.runner.AndroidJUnitRunner \
    | tee "$reports/instrumentation.txt"

# Android's instrument command can exit zero when JUnit fails. Require its result.
grep -q '^OK (1 test)' "$reports/instrumentation.txt"
adb exec-out run-as swift.video.module.test cat coverage.ec > "$reports/media3.ec"
test -s "$reports/media3.ec"
