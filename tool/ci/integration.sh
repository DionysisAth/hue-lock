#!/usr/bin/env bash
# Runs the on-device game-flow test. Prints the test output without
# stack-frame noise, and the device's app log if it fails.
#
#   tool/ci/integration.sh
set -u
timeout 900 flutter test integration_test/app_test.dart -d emulator-5554 \
  --reporter expanded > integration.log 2>&1
status=$?
[ "$status" -eq 124 ] && echo "::error::integration test timed out after 15 min"
grep -vE '^(#[0-9]+ |\(elided|── callback)' integration.log | tail -n 250
if [ "$status" -ne 0 ]; then
  echo "----- device log -----"
  timeout 30 adb logcat -d -v time \
    | grep -E "flutter|AndroidRuntime|FATAL|hue_lock|ANR|Dart|VM Service" \
    | tail -n 150
fi
exit "$status"
