#!/usr/bin/env bash

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP_ROOT="$(mktemp -d)"
ANDROID_JNI_DIR="$ROOT/android/app/src/main/jniLibs"

cleanup() {
  rm -rf "$TMP_ROOT"
  rm -rf "$ROOT/build/native-artifacts"
  rm -rf "$ROOT/dist/linux" "$ROOT/dist/ios"
  rm -rf "$ANDROID_JNI_DIR"
}
trap cleanup EXIT

fail() {
  echo "[FAIL] $*" >&2
  exit 1
}

assert_file_exists() {
  local path="$1"
  [[ -e "$path" ]] || fail "Expected file to exist: $path"
}

assert_file_missing() {
  local path="$1"
  [[ ! -e "$path" ]] || fail "Expected file to be absent: $path"
}

test_android_syncs_jni_libs_into_app_tree() {
  echo "[test] android syncs JNI libs into app tree"
  local src_dir="$TMP_ROOT/android-libs"
  mkdir -p "$src_dir/arm64-v8a"
  printf 'fake-so' > "$src_dir/arm64-v8a/libtim2tox_ffi.so"

  TIM2TOX_ANDROID_LIB_DIR="$src_dir" \
    bash "$ROOT/tool/ci/build_tim2tox.sh" --target android --mode release

  assert_file_exists "$ROOT/build/native-artifacts/android/jniLibs/arm64-v8a/libtim2tox_ffi.so"
  assert_file_exists "$ANDROID_JNI_DIR/arm64-v8a/libtim2tox_ffi.so"
}

test_linux_package_includes_libsodium() {
  echo "[test] linux package includes libsodium payload"
  mkdir -p "$ROOT/build/linux/x64/release/bundle/lib"
  printf 'fake-exe' > "$ROOT/build/linux/x64/release/bundle/toxee"
  printf 'fake-ffi' > "$ROOT/build/linux/x64/release/bundle/lib/libtim2tox_ffi.so"
  mkdir -p "$ROOT/build/native-artifacts/linux"
  printf 'fake-ffi' > "$ROOT/build/native-artifacts/linux/libtim2tox_ffi.so"
  printf 'fake-sodium' > "$ROOT/build/native-artifacts/linux/libsodium.so.23"

  bash "$ROOT/tool/ci/package_artifacts.sh" --target linux --mode release

  tar -tzf "$ROOT/dist/linux/toxee-linux-x64-release.tar.gz" | grep -q 'libsodium.so.23' || \
    fail "Expected Linux archive to contain libsodium.so.23"
}

test_ios_unsigned_build_is_not_packaged_as_installable_zip() {
  echo "[test] unsigned iOS build is not packaged as installable zip"
  rm -rf "$ROOT/dist/ios" "$ROOT/build/ios/iphoneos"
  mkdir -p "$ROOT/build/ios/iphoneos/Runner.app/Frameworks"

  bash "$ROOT/tool/ci/package_artifacts.sh" --target ios --mode release

  assert_file_missing "$ROOT/dist/ios/toxee-ios-release.zip"
  assert_file_missing "$ROOT/dist/ios/toxee-ios-release.ipa"
  assert_file_exists "$ROOT/dist/ios/NOTES.txt"
}

test_ios_signed_build_is_packaged_as_ipa() {
  echo "[test] signed iOS build is packaged as ipa"
  rm -rf "$ROOT/dist/ios" "$ROOT/build/ios/iphoneos"
  mkdir -p "$ROOT/build/ios/iphoneos/Runner.app/Frameworks"
  printf 'signed' > "$ROOT/build/ios/iphoneos/Runner.app/embedded.mobileprovision"
  mkdir -p "$ROOT/build/native-artifacts/ios/tim2tox_ffi.framework"
  printf 'ffi-framework' > "$ROOT/build/native-artifacts/ios/tim2tox_ffi.framework/tim2tox_ffi"

  bash "$ROOT/tool/ci/package_artifacts.sh" --target ios --mode release

  assert_file_exists "$ROOT/dist/ios/toxee-ios-release.ipa"
  unzip -l "$ROOT/dist/ios/toxee-ios-release.ipa" | grep -q 'Payload/Runner.app/Frameworks/tim2tox_ffi.framework/tim2tox_ffi' || \
    fail "Expected signed IPA to contain injected tim2tox_ffi framework"
}

test_workflow_does_not_use_secrets_in_if_conditions() {
  echo "[test] workflow avoids secrets in if conditions"
  if rg -n '^[[:space:]]*if:.*secrets\\.' "$ROOT/.github/workflows/build-packages.yml" >/dev/null; then
    fail "Workflow still uses secrets directly in if conditions"
  fi
}

test_analyze_workflow_tolerates_existing_warnings() {
  echo "[test] analyze workflow is non-fatal for existing warnings"
  rg -n 'flutter analyze --no-fatal-warnings --no-fatal-infos' "$ROOT/.github/workflows/analyze.yml" >/dev/null || \
    fail "Analyze workflow still treats warnings as fatal"
}

test_android_syncs_jni_libs_into_app_tree
test_linux_package_includes_libsodium
test_ios_unsigned_build_is_not_packaged_as_installable_zip
test_ios_signed_build_is_packaged_as_ipa
test_workflow_does_not_use_secrets_in_if_conditions
test_analyze_workflow_tolerates_existing_warnings

echo "[PASS] all packaging regression tests passed"
