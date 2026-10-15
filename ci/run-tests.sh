#!/usr/bin/env bash
# Runs the unit tests on the first available iPhone simulator.
set -uo pipefail

UDID=$(xcrun simctl list devices available -j \
  | jq -r '[.devices | to_entries[] | select(.key | contains("iOS")) | .value[] | select(.name | startswith("iPhone"))][0].udid')
echo "Testing on simulator $UDID"

xcodebuild test \
  -project Tabby.xcodeproj \
  -scheme Tabby \
  -destination "id=$UDID" \
  CODE_SIGNING_ALLOWED=NO \
  > build.log 2>&1
status=$?

grep -E "error:|Test Case .*(passed|failed)|\*\* (TEST|BUILD)" build.log || true
exit $status
