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

test_ios_unsigned_build_is_packaged_as_validation_ipa() {
  echo "[test] unsigned iOS build is packaged as validation ipa"
  rm -rf "$ROOT/dist/ios" "$ROOT/build/ios/iphoneos"
  mkdir -p "$ROOT/build/ios/iphoneos/Runner.app/Frameworks"

  bash "$ROOT/tool/ci/package_artifacts.sh" --target ios --mode release

  assert_file_missing "$ROOT/dist/ios/toxee-ios-release.zip"
  assert_file_exists "$ROOT/dist/ios/toxee-ios-release.ipa"
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
  local zip_listing
  zip_listing="$(unzip -l "$ROOT/dist/ios/toxee-ios-release.ipa")"
  grep -q 'Payload/Runner.app/Frameworks/tim2tox_ffi.framework/tim2tox_ffi' <<<"$zip_listing" || \
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
  rg -n 'flutter analyze lib tool --no-fatal-warnings --no-fatal-infos' "$ROOT/.github/workflows/analyze.yml" >/dev/null || \
    fail "Analyze workflow still treats warnings as fatal"
}

test_windows_release_workflow_uses_wix_for_msi() {
  echo "[test] windows workflow installs WiX and expects MSI packaging"
  rg -n 'Add WiX to PATH \(Windows\)|choco install wixtoolset|cpack -C Release -G "WIX"|\\.msi' \
    "$ROOT/.github/workflows/build-packages.yml" "$ROOT/tool/ci/package_artifacts.sh" >/dev/null || \
    fail "Windows release flow does not appear to produce MSI installers"
  rg -n 'CPACK_GENERATOR "WIX"|CPACK_WIX_UPGRADE_GUID|install\(' \
    "$ROOT/tool/ci/windows-installer/CMakeLists.txt" >/dev/null || \
    fail "Dedicated Windows MSI packaging config is missing"
}

test_release_publish_filters_non_installable_mobile_assets() {
  echo "[test] release publish filters non-installable mobile assets"
  local artifacts_dir="$TMP_ROOT/release-artifacts"
  mkdir -p "$artifacts_dir/toxee-android-release" "$artifacts_dir/toxee-ios-release" "$artifacts_dir/toxee-windows-release"

  printf 'apk' > "$artifacts_dir/toxee-android-release/app-release.apk"
  printf 'aab' > "$artifacts_dir/toxee-android-release/app-release.aab"
  cat > "$artifacts_dir/toxee-android-release/NOTES.txt" <<'EOF'
No Android Tim2Tox JNI libraries were staged. APK/AAB were built, but runtime native loading still needs libtim2tox_ffi.so packaging.
EOF

  printf 'ipa' > "$artifacts_dir/toxee-ios-release/toxee-ios-release.ipa"
  cat > "$artifacts_dir/toxee-ios-release/NOTES.txt" <<'EOF'
Packaged unsigned iOS app as IPA.
Unsigned iOS IPA was packaged without an injected Tim2Tox FFI artifact.
EOF

  printf 'msi' > "$artifacts_dir/toxee-windows-release/toxee-windows-x64-release.msi"
  cat > "$artifacts_dir/toxee-windows-release/NOTES.txt" <<'EOF'
Bundled tim2tox_ffi.dll into Windows package.
Bundled libsodium.dll into Windows package.
EOF

  PATH="/usr/bin:/bin" \
    RELEASE_DRY_RUN=1 RELEASE_TAG=vtest RELEASE_ARTIFACTS_DIR="$artifacts_dir" \
    bash "$ROOT/tool/ci/publish_release.sh"

  assert_file_exists "$ROOT/dist/github-release/toxee-windows-x64-release.msi"
  assert_file_missing "$ROOT/dist/github-release/app-release.apk"
  assert_file_missing "$ROOT/dist/github-release/app-release.aab"
  assert_file_missing "$ROOT/dist/github-release/toxee-ios-release.ipa"
}

test_release_publish_keeps_one_installer_per_platform() {
  echo "[test] release publish keeps one installer per platform"
  local artifacts_dir="$TMP_ROOT/release-installers"
  mkdir -p \
    "$artifacts_dir/toxee-linux-release" \
    "$artifacts_dir/toxee-macos-release" \
    "$artifacts_dir/toxee-windows-release" \
    "$artifacts_dir/toxee-android-release" \
    "$artifacts_dir/toxee-ios-release"

  printf 'appimage' > "$artifacts_dir/toxee-linux-release/toxee-linux-x64-release.AppImage"
  printf 'linux-tar' > "$artifacts_dir/toxee-linux-release/toxee-linux-x64-release.tar.gz"
  cat > "$artifacts_dir/toxee-linux-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.so into Linux bundle.
EOF

  printf 'dmg' > "$artifacts_dir/toxee-macos-release/toxee-macos-release.dmg"
  printf 'mac-zip' > "$artifacts_dir/toxee-macos-release/toxee-macos-release.zip"
  cat > "$artifacts_dir/toxee-macos-release/NOTES.txt" <<'EOF'
Bundled libtim2tox_ffi.dylib into macOS app.
EOF

  printf 'msi' > "$artifacts_dir/toxee-windows-release/toxee-windows-x64-release.msi"
  printf 'win-zip' > "$artifacts_dir/toxee-windows-release/toxee-windows-x64-release.zip"
  cat > "$artifacts_dir/toxee-windows-release/NOTES.txt" <<'EOF'
Bundled tim2tox_ffi.dll into Windows package.
EOF

  printf 'apk' > "$artifacts_dir/toxee-android-release/app-release.apk"
  printf 'aab' > "$artifacts_dir/toxee-android-release/app-release.aab"
  cat > "$artifacts_dir/toxee-android-release/NOTES.txt" <<'EOF'
Android build used repository-provided Tim2Tox JNI libraries.
EOF

  printf 'ipa' > "$artifacts_dir/toxee-ios-release/toxee-ios-release.ipa"
  cat > "$artifacts_dir/toxee-ios-release/NOTES.txt" <<'EOF'
Packaged signed iOS app as IPA.
Injected Tim2Tox FFI artifact into signed iOS app before IPA packaging.
EOF

  PATH="/usr/bin:/bin" \
    RELEASE_DRY_RUN=1 RELEASE_TAG=vtest RELEASE_ARTIFACTS_DIR="$artifacts_dir" \
    bash "$ROOT/tool/ci/publish_release.sh"

  assert_file_exists "$ROOT/dist/github-release/toxee-linux-x64-release.AppImage"
  assert_file_exists "$ROOT/dist/github-release/toxee-macos-release.dmg"
  assert_file_exists "$ROOT/dist/github-release/toxee-windows-x64-release.msi"
  assert_file_exists "$ROOT/dist/github-release/app-release.apk"
  assert_file_exists "$ROOT/dist/github-release/toxee-ios-release.ipa"
  assert_file_exists "$ROOT/dist/github-release/SHA256SUMS.txt"

  assert_file_missing "$ROOT/dist/github-release/toxee-linux-x64-release.tar.gz"
  assert_file_missing "$ROOT/dist/github-release/toxee-macos-release.zip"
  assert_file_missing "$ROOT/dist/github-release/toxee-windows-x64-release.zip"
  assert_file_missing "$ROOT/dist/github-release/app-release.aab"
  assert_file_missing "$ROOT/dist/github-release/BUILD-NOTES.txt"
}

test_android_syncs_jni_libs_into_app_tree
test_linux_package_includes_libsodium
test_ios_unsigned_build_is_packaged_as_validation_ipa
test_ios_signed_build_is_packaged_as_ipa
test_workflow_does_not_use_secrets_in_if_conditions
test_analyze_workflow_tolerates_existing_warnings
test_windows_release_workflow_uses_wix_for_msi
test_release_publish_filters_non_installable_mobile_assets
test_release_publish_keeps_one_installer_per_platform

echo "[PASS] all packaging regression tests passed"
