#!/usr/bin/env bash
set -euo pipefail
adb logcat -c
adb install -r build/app/outputs/flutter-apk/app-x86_64-release.apk
adb shell am start -W -n com.tripcal.app/.MainActivity
sleep 15
adb logcat -d -v time > android-startup.log
adb shell uiautomator dump /sdcard/window.xml >/dev/null
adb pull /sdcard/window.xml android-window.xml >/dev/null
if ! adb shell pidof com.tripcal.app >/dev/null; then
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
if grep -E 'FATAL EXCEPTION|Fatal signal|\[ERROR:flutter' android-startup.log; then
  echo 'Fatal error detected in logcat.'
  exit 1
fi
echo 'Release app process and home screen are visible.'
