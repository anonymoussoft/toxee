#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET=""
MODE="release"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target)
      TARGET="${2:-}"
      shift 2
      ;;
    --mode)
      MODE="${2:-}"
      shift 2
      ;;
    --help|-h)
      cat <<'EOF'
Usage: package_artifacts.sh --target <linux|windows|macos|android|ios> [--mode <debug|profile|release>]
EOF
      exit 0
      ;;
    *)
      ci_die "Unknown option: $1"
      ;;
  esac
done

[[ -n "$TARGET" ]] || ci_die "--target is required"

REPO_ROOT="$(ci_repo_root)"
DIST_DIR="$REPO_ROOT/dist/$TARGET"
NATIVE_DIR="$REPO_ROOT/build/native-artifacts/$TARGET"
MODE_DIR="$(ci_mode_dirname "$MODE")"

ci_reset_dir "$DIST_DIR"

write_note() {
  local note_file="$DIST_DIR/NOTES.txt"
  printf '%s\n' "$1" >> "$note_file"
}

package_linux() {
  local bundle_dir="$REPO_ROOT/build/linux/x64/$MODE/bundle"
  local staged_dir="$DIST_DIR/toxee-linux-x64"
  local archive_path="$DIST_DIR/toxee-linux-x64-$MODE.tar.gz"
  local bundled_sodium="false"

  [[ -d "$bundle_dir" ]] || ci_die "Linux bundle not found: $bundle_dir"

  mkdir -p "$bundle_dir/lib"
  if [[ -f "$NATIVE_DIR/libtim2tox_ffi.so" ]]; then
    cp "$NATIVE_DIR/libtim2tox_ffi.so" "$bundle_dir/lib/"
    write_note "Bundled libtim2tox_ffi.so into Linux bundle."
  else
    write_note "libtim2tox_ffi.so was not found. The Linux bundle was packaged without the Tim2Tox native library."
  fi

  while IFS= read -r sodium_file; do
    [[ -n "$sodium_file" ]] || continue
    cp -a "$sodium_file" "$bundle_dir/lib/"
    bundled_sodium="true"
  done < <(find "$NATIVE_DIR" -maxdepth 1 \( -type f -o -type l \) -name 'libsodium*.so*' | sort)

  if [[ "$bundled_sodium" == "true" ]]; then
    write_note "Bundled Linux libsodium runtime dependency."
  else
    write_note "Linux libsodium runtime dependency was not captured; target host may need libsodium preinstalled."
  fi

  if command -v patchelf >/dev/null 2>&1 && command -v file >/dev/null 2>&1; then
    if file "$bundle_dir/lib/libtim2tox_ffi.so" | grep -qi 'ELF'; then
      patchelf --set-rpath '$ORIGIN' "$bundle_dir/lib/libtim2tox_ffi.so"
      write_note "Normalized Linux FFI rpath to \$ORIGIN."
    fi
  fi

  rm -rf "$staged_dir"
  mkdir -p "$staged_dir"
  cp -R "$bundle_dir"/. "$staged_dir/"
  tar -czf "$archive_path" -C "$DIST_DIR" "$(basename "$staged_dir")"
  rm -rf "$staged_dir"
  ci_log "Created Linux archive: $archive_path"
}

package_windows() {
  local runner_dir="$REPO_ROOT/build/windows/x64/runner/$MODE_DIR"
  local staged_dir="$DIST_DIR/toxee-windows-x64"
  local archive_path="$DIST_DIR/toxee-windows-x64-$MODE.zip"

  [[ -d "$runner_dir" ]] || ci_die "Windows runner output not found: $runner_dir"

  rm -rf "$staged_dir"
  mkdir -p "$staged_dir"
  cp -R "$runner_dir"/. "$staged_dir/"

  if [[ -f "$NATIVE_DIR/tim2tox_ffi.dll" ]]; then
    cp "$NATIVE_DIR/tim2tox_ffi.dll" "$staged_dir/"
    write_note "Bundled tim2tox_ffi.dll into Windows package."
  else
    write_note "tim2tox_ffi.dll was not found. The Windows package was created without the Tim2Tox native library."
  fi

  if [[ -f "$NATIVE_DIR/libsodium.dll" ]]; then
    cp "$NATIVE_DIR/libsodium.dll" "$staged_dir/"
    write_note "Bundled libsodium.dll into Windows package."
  fi

  powershell.exe -NoLogo -NoProfile -Command \
    "Compress-Archive -Path '$(ci_windows_path "$staged_dir")' -DestinationPath '$(ci_windows_path "$archive_path")' -Force" \
    >/dev/null
  rm -rf "$staged_dir"
  ci_log "Created Windows archive: $archive_path"
}

package_macos() {
  local app_bundle="$REPO_ROOT/build/macos/Build/Products/$MODE_DIR/Toxee.app"
  local archive_path="$DIST_DIR/toxee-macos-$MODE.zip"
  local macos_dir="$app_bundle/Contents/MacOS"
  local ffi_lib="$NATIVE_DIR/libtim2tox_ffi.dylib"
  local sodium_lib

  if [[ ! -d "$app_bundle" ]]; then
    app_bundle="$(find "$REPO_ROOT/build/macos/Build/Products/$MODE_DIR" -maxdepth 1 -type d -name '*.app' | head -n 1 || true)"
  fi
  [[ -n "$app_bundle" && -d "$app_bundle" ]] || ci_die "macOS app bundle not found under build/macos/Build/Products/$MODE_DIR"

  mkdir -p "$macos_dir"

  if [[ -f "$ffi_lib" ]]; then
    cp "$ffi_lib" "$macos_dir/"
    write_note "Bundled libtim2tox_ffi.dylib into macOS app."

    sodium_lib="$(find "$NATIVE_DIR" -maxdepth 1 -type f -name 'libsodium*.dylib' | head -n 1 || true)"
    if [[ -n "$sodium_lib" ]]; then
      cp "$sodium_lib" "$macos_dir/"
      local old_path new_name
      old_path="$(otool -L "$ffi_lib" | awk '/libsodium.*dylib/ {print $1; exit}' || true)"
      new_name="$(basename "$sodium_lib")"
      if [[ -n "$old_path" ]]; then
        install_name_tool -change "$old_path" "@loader_path/$new_name" "$macos_dir/$(basename "$ffi_lib")"
      fi
      write_note "Bundled $(basename "$sodium_lib") into macOS app."
    fi
  else
    write_note "libtim2tox_ffi.dylib was not found. The macOS app was packaged without the Tim2Tox native library."
  fi

  ditto -c -k --sequesterRsrc --keepParent "$app_bundle" "$archive_path"
  ci_log "Created macOS archive: $archive_path"
}

package_android() {
  local apk_path="$REPO_ROOT/build/app/outputs/flutter-apk/app-$MODE.apk"
  local aab_path="$REPO_ROOT/build/app/outputs/bundle/$MODE/app-$MODE.aab"

  [[ -f "$apk_path" ]] || ci_die "Android APK not found: $apk_path"
  cp "$apk_path" "$DIST_DIR/"
  ci_log "Captured Android APK: $apk_path"

  if [[ -f "$aab_path" ]]; then
    cp "$aab_path" "$DIST_DIR/"
    ci_log "Captured Android App Bundle: $aab_path"
  else
    write_note "Android App Bundle was not produced."
  fi

  if [[ -d "$NATIVE_DIR/jniLibs" ]] && find "$NATIVE_DIR/jniLibs" -type f -name "libtim2tox_ffi.so" | grep -q .; then
    write_note "Android build used repository-provided Tim2Tox JNI libraries."
  else
    write_note "No Android Tim2Tox JNI libraries were staged. APK/AAB were built, but runtime native loading still needs libtim2tox_ffi.so packaging."
  fi
}

package_ios() {
  local app_bundle="$REPO_ROOT/build/ios/iphoneos/Runner.app"
  local archive_path="$DIST_DIR/toxee-ios-$MODE.ipa"
  local frameworks_dir="$app_bundle/Frameworks"
  local framework_src="$NATIVE_DIR/tim2tox_ffi.framework"
  local dylib_src="$NATIVE_DIR/libtim2tox_ffi.dylib"
  local payload_dir="$DIST_DIR/Payload"
  local signed_marker="$app_bundle/embedded.mobileprovision"
  local injected="false"

  [[ -d "$app_bundle" ]] || ci_die "iOS app bundle not found: $app_bundle"

  mkdir -p "$frameworks_dir"
  if [[ -d "$framework_src" ]]; then
    rm -rf "$frameworks_dir/tim2tox_ffi.framework"
    cp -R "$framework_src" "$frameworks_dir/"
    injected="true"
  elif [[ -f "$dylib_src" ]]; then
    cp "$dylib_src" "$frameworks_dir/"
    injected="true"
  fi

  if [[ -f "$signed_marker" ]]; then
    mkdir -p "$payload_dir"
    cp -R "$app_bundle" "$payload_dir/"
    (cd "$DIST_DIR" && zip -qry "$(basename "$archive_path")" Payload)
    rm -rf "$payload_dir"
    ci_log "Created iOS IPA: $archive_path"
    write_note "Packaged signed iOS app as IPA."
    if [[ "$injected" == "true" ]]; then
      write_note "Injected Tim2Tox FFI artifact into signed iOS app before IPA packaging."
    else
      write_note "Signed iOS IPA was packaged without an injected Tim2Tox FFI artifact."
    fi
    return
  fi

  if [[ "${IOS_SIGNING_READY:-false}" == "true" ]]; then
    ci_die "iOS signing was configured, but the built app bundle is not signed (missing embedded.mobileprovision)."
  fi

  if [[ "$injected" == "true" ]]; then
    write_note "Unsigned iOS build detected; FFI artifacts were not packaged as an installable IPA."
  else
    write_note "Unsigned iOS build detected; skipping installable package creation."
  fi
}

case "$TARGET" in
  linux) package_linux ;;
  windows) package_windows ;;
  macos) package_macos ;;
  android) package_android ;;
  ios) package_ios ;;
  *) ci_die "Unsupported target: $TARGET" ;;
esac
