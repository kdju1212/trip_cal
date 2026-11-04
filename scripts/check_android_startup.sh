#!/usr/bin/env bash
set -euo pipefail
apk_path="${1:-build/app/outputs/flutter-apk/app-x86_64-release.apk}"
app_id="${2:-com.tripcal.app}"
adb wait-for-device
# Package manager may restart while a fresh Android 17 image finishes booting.
sleep 30
adb logcat -c
trap 'adb logcat -d -v time > android-startup.log || true' EXIT
if ! adb install --no-streaming -r "$apk_path"; then
  sleep 30
  adb wait-for-device
  adb install --no-streaming -r "$apk_path"
fi
adb shell am start -W -n "$app_id/com.tripcal.app.MainActivity"
sleep 15
adb logcat -d -v time > android-startup.log
adb shell uiautomator dump /sdcard/window.xml >/dev/null
adb pull /sdcard/window.xml android-window.xml >/dev/null
if ! adb shell pidof "$app_id" >/dev/null; then
  tail -n 500 android-startup.log
  echo 'App process exited during startup.'
  exit 1
fi
if ! grep -q '나의 여행\|새 여행\|여행 준비 도우미' android-window.xml; then
  tail -n 500 android-startup.log
  cat android-window.xml
  echo 'Home screen did not appear.'
  exit 1
fi
if grep -E '\[ERROR:flutter' android-startup.log; then
  echo 'Fatal error detected in logcat.'
  exit 1
fi
echo 'Release app process and home screen are visible.'
