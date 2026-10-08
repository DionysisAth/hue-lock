#!/usr/bin/env bash
# Installs the release APK on the connected emulator, launches it, plays a
# few taps and fails if the app crashed or exited. Collects logcat and a
# screenshot into ci-out/ for debugging.
#
#   tool/ci/smoke_release.sh hue-lock.apk
set -u
APK=$1
PKG=com.huelock.hue_lock
OUT=ci-out
mkdir -p "$OUT"

alive() { [ -n "$(adb shell pidof "$PKG" | tr -d '\r')" ]; }

fail() {
  echo "::error::$1"
  adb logcat -d -b crash > "$OUT/crash.log" 2>&1
  adb logcat -d -v time > "$OUT/logcat.log" 2>&1
  echo "----- crash buffer -----"
  cat "$OUT/crash.log"
  echo "----- app / runtime log -----"
  grep -E "AndroidRuntime|FATAL|flutter|$PKG|DEBUG|libc|Unable|Exception" "$OUT/logcat.log" | tail -n 200
  adb exec-out screencap -p > "$OUT/release.png" 2>/dev/null
  exit 1
}

adb uninstall "$PKG" > /dev/null 2>&1
adb install "$APK" || fail "install failed"
adb logcat -c
adb shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 > /dev/null
sleep 15
alive || fail "release app is not running 15 s after launch"

# Tap the middle of the screen: start a run, miss, restart, and so on.
size=$(adb shell wm size | grep -oE '[0-9]+x[0-9]+' | tail -n 1)
w=${size%x*}; h=${size#*x}
for i in 1 2 3 4 5 6; do
  adb shell input tap $((w / 2)) $((h * 3 / 10))
  sleep 1.5
done
alive || fail "release app died while playing"

adb exec-out screencap -p > "$OUT/release.png"
adb logcat -d -v time > "$OUT/logcat.log"
echo "Release app launched and survived play."
