#!/usr/bin/env bash
# Confirms that the Gradle guards in android/app/build.gradle.kts stop unsafe release builds.
# Run from the repository root after `flutter pub get`. Each case is expected to fail early.
set -uo pipefail

key_file=android/key.properties
created_key=false
cleanup() { if [ "$created_key" = true ]; then rm -f "$key_file"; fi; }
trap cleanup EXIT

expect_rejected() {
  local label=$1 message=$2
  shift 2
  local log
  log=$(mktemp)
  if "$@" >"$log" 2>&1; then
    echo "FAIL: $label was built, but it should have been rejected."
    exit 1
  fi
  if ! grep -q "$message" "$log"; then
    echo "FAIL: $label failed for a different reason:"
    tail -n 60 "$log"
    exit 1
  fi
  echo "OK: $label was rejected."
}

# 8. Shrinking must never run. The self-test property turns it on to prove the guard still fires.
ORG_GRADLE_PROJECT_releaseGuardSelfTest=true expect_rejected \
  "a release APK with code shrinking" "Code shrinking must stay off" \
  flutter build apk --release --no-shrink --split-per-abi --target-platform android-arm64

# 1. A Play bundle must not carry the ad server settings while ads are off.
# The signing guard needs a key file to exist; this placeholder is never used for signing
# because the build stops during configuration.
if [ ! -e "$key_file" ]; then
  printf 'storePassword=unused\nkeyPassword=unused\nkeyAlias=unused\nstoreFile=/nonexistent/guard-check.jks\n' >"$key_file"
  created_key=true
fi
expect_rejected \
  "a release bundle with ad server settings" "must not include SUPABASE_URL or SUPABASE_ANON_KEY" \
  flutter build appbundle --release --no-shrink --dart-define=SUPABASE_URL=https://example.invalid
