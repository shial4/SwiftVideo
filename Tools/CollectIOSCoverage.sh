#!/usr/bin/env bash
# Copyright 2026 Software Deck Pty Ltd
# SPDX-License-Identifier: Apache-2.0

# Xcode's xccov summary can omit Swift package sources. Export the tested
# binary's LLVM mapping with only the profiles named by this result bundle.
set -euo pipefail

result_bundle="${1:?Set the passing iOS xcresult path.}"
derived_data="${2:?Set the matching derived data path.}"
output="${3:?Set the output coverage directory.}"
mkdir -p "$output"
xcrun xcresulttool get test-results summary --path "$result_bundle" > "$output/ios-tests.json"
device_ids=$(python3 - "$output/ios-tests.json" <<'PY'
import json, sys
summary = json.load(open(sys.argv[1]))
if summary["result"] != "Passed" or summary["failedTests"] or not summary["passedTests"]:
    sys.exit("iOS coverage requires a passing, nonempty test run")
print("\n".join(sorted({entry["device"]["deviceId"]
                         for entry in summary["devicesAndConfigurations"]})))
PY
)
profiles=()
while IFS= read -r device_id; do
    test -n "$device_id"
    profile="$derived_data/Build/ProfileData/$device_id/Coverage.profdata"
    test -s "$profile"
    profiles+=("$profile")
done <<< "$device_ids"
xcrun llvm-profdata merge -sparse "${profiles[@]}" -o "$output/ios.profdata"
xcrun llvm-cov export \
    "$derived_data/Build/Products/Debug-iphonesimulator/SwiftVideoTests.xctest/SwiftVideoTests" \
    -instr-profile="$output/ios.profdata" > "$output/ios-raw.json"
swift Tools/Coverage.swift ios "$output/ios-raw.json" "$output/ios.json" 90
