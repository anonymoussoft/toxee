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
Usage: build_tim2tox.sh --target <linux|windows|macos|android|ios> [--mode <debug|profile|release>]
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
TIM2TOX_DIR="$REPO_ROOT/third_party/tim2tox"
OUTPUT_DIR="$REPO_ROOT/build/native-artifacts/$TARGET"

[[ -d "$TIM2TOX_DIR" ]] || ci_die "tim2tox submodule not found: $TIM2TOX_DIR"

ci_reset_dir "$OUTPUT_DIR"

bootstrap_tim2tox_submodules() {
  if [[ -f "$TIM2TOX_DIR/.gitmodules" ]] && { [[ -d "$TIM2TOX_DIR/.git" ]] || [[ -f "$TIM2TOX_DIR/.git" ]]; }; then
    ci_log "Ensuring tim2tox nested submodules are initialized"
    (cd "$TIM2TOX_DIR" && git submodule update --init --recursive)
  fi
}

capture_linux_shared_library() {
  local library_path="$1"
  [[ -n "$library_path" && -e "$library_path" ]] || return 0

  local resolved_path
  resolved_path="$(readlink -f "$library_path" 2>/dev/null || printf '%s\n' "$library_path")"

  cp -P "$library_path" "$OUTPUT_DIR/"
  if [[ "$resolved_path" != "$library_path" && -f "$resolved_path" ]]; then
    cp "$resolved_path" "$OUTPUT_DIR/"
  fi
}

configure_args=(
  -DBUILD_FFI=ON
  -DBUILD_TOXAV=OFF
  -DMUST_BUILD_TOXAV=OFF
  -DDHT_BOOTSTRAP=OFF
  -DBOOTSTRAP_DAEMON=OFF
  -DENABLE_SHARED=OFF
  -DENABLE_STATIC=ON
  -DUNITTEST=OFF
  -DAUTOTEST=OFF
  -DBUILD_MISC_TESTS=OFF
  -DBUILD_FUN_UTILS=OFF
  -DBUILD_FUZZ_TESTS=OFF
  -DUSE_IPV6=ON
  -DEXPERIMENTAL_API=OFF
  -DERROR=ON
  -DWARNING=ON
  -DINFO=ON
  -DTRACE=OFF
  -DDEBUG=OFF
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

build_desktop_target() {
  local target="$1"
  local build_dir="$TIM2TOX_DIR/build/ci-$target"
  local lib_pattern=""
  local built_lib=""

  bootstrap_tim2tox_submodules
  mkdir -p "$build_dir"

  case "$target" in
    linux)
      lib_pattern="libtim2tox_ffi.so"
      ci_log "Configuring tim2tox for Linux"
      cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format -include arpa/inet.h" \
        -DCMAKE_C_FLAGS="-Wno-error=format" \
        "${configure_args[@]}"
      ;;
    macos)
      lib_pattern="libtim2tox_ffi.dylib"
      ci_log "Configuring tim2tox for macOS"
      cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
        -DCMAKE_BUILD_TYPE=Release \
        -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format" \
        -DCMAKE_C_FLAGS="-Wno-error=format" \
        "${configure_args[@]}"
      ;;
    windows)
      lib_pattern="tim2tox_ffi.dll"
      ci_log "Configuring tim2tox for Windows"
      local source_dir_win build_dir_win
      source_dir_win="$(ci_windows_path "$TIM2TOX_DIR")"
      build_dir_win="$(ci_windows_path "$build_dir")"
      if [[ -n "${VCPKG_ROOT:-}" ]]; then
        local vcpkg_root_win
        vcpkg_root_win="$(ci_windows_path "$VCPKG_ROOT")"
        VCPKG_ROOT="$vcpkg_root_win" cmake -S "$source_dir_win" -B "$build_dir_win" -G "Visual Studio 17 2022" -A x64 "${configure_args[@]}"
      else
        cmake -S "$source_dir_win" -B "$build_dir_win" -G "Visual Studio 17 2022" -A x64 "${configure_args[@]}"
      fi
      ;;
    *)
      ci_die "Unsupported desktop target: $target"
      ;;
  esac

  ci_log "Building tim2tox_ffi for $target"
  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name "$lib_pattern" | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate $lib_pattern under $build_dir"
  cp "$built_lib" "$OUTPUT_DIR/"
  ci_log "Captured native library: $built_lib"

  if [[ "$target" == "windows" && -n "${VCPKG_ROOT:-}" ]]; then
    ci_copy_matching_file "$VCPKG_ROOT/installed/x64-windows" "libsodium.dll" "$OUTPUT_DIR" >/dev/null || \
      ci_warn "libsodium.dll not found under $VCPKG_ROOT/installed/x64-windows"
  fi

  if [[ "$target" == "linux" ]]; then
    local sodium_dep
    sodium_dep="$(ldd "$built_lib" | awk '/libsodium/ {print $3; exit}' || true)"
    if [[ -n "$sodium_dep" && -e "$sodium_dep" ]]; then
      capture_linux_shared_library "$sodium_dep"
      ci_log "Captured Linux dependency: $sodium_dep"
    else
      ci_warn "Could not resolve libsodium dependency from $built_lib"
    fi
  fi

  if [[ "$target" == "macos" ]]; then
    local sodium_dep
    sodium_dep="$(otool -L "$built_lib" | awk '/libsodium.*dylib/ {print $1; exit}' || true)"
    if [[ -n "$sodium_dep" && -f "$sodium_dep" ]]; then
      cp "$sodium_dep" "$OUTPUT_DIR/"
      ci_log "Captured macOS dependency: $sodium_dep"
    fi
  fi
}

sync_android_ffi_libs() {
  local source_dir="${TIM2TOX_ANDROID_LIB_DIR:-}"
  local repo_jni_libs="$REPO_ROOT/android/app/src/main/jniLibs"
  if [[ -z "$source_dir" ]]; then
    if [[ -d "$repo_jni_libs" ]] && find "$repo_jni_libs" -type f -name "libtim2tox_ffi.so" | grep -q .; then
      source_dir="$repo_jni_libs"
    fi
  fi

  if [[ -z "$source_dir" ]]; then
    ci_warn "No Android Tim2Tox JNI libraries found; Android artifacts will be built without bundled libtim2tox_ffi.so"
    return
  fi

  [[ -d "$source_dir" ]] || ci_die "TIM2TOX_ANDROID_LIB_DIR is not a directory: $source_dir"
  mkdir -p "$OUTPUT_DIR/jniLibs"
  cp -R "$source_dir"/. "$OUTPUT_DIR/jniLibs/"
  if [[ "$source_dir" != "$repo_jni_libs" ]]; then
    rm -rf "$repo_jni_libs"
    mkdir -p "$repo_jni_libs"
    cp -R "$source_dir"/. "$repo_jni_libs/"
    ci_log "Staged Android JNI libraries into $repo_jni_libs"
  fi
  ci_log "Synced Android JNI libraries from $source_dir"
}

sync_ios_ffi_artifacts() {
  local copied="false"

  if [[ -n "${TIM2TOX_IOS_FRAMEWORK_PATH:-}" ]]; then
    [[ -d "${TIM2TOX_IOS_FRAMEWORK_PATH}" ]] || ci_die "TIM2TOX_IOS_FRAMEWORK_PATH does not exist: ${TIM2TOX_IOS_FRAMEWORK_PATH}"
    cp -R "${TIM2TOX_IOS_FRAMEWORK_PATH}" "$OUTPUT_DIR/"
    copied="true"
    ci_log "Captured iOS framework from ${TIM2TOX_IOS_FRAMEWORK_PATH}"
  fi

  if [[ -n "${TIM2TOX_IOS_DYLIB_PATH:-}" ]]; then
    [[ -f "${TIM2TOX_IOS_DYLIB_PATH}" ]] || ci_die "TIM2TOX_IOS_DYLIB_PATH does not exist: ${TIM2TOX_IOS_DYLIB_PATH}"
    cp "${TIM2TOX_IOS_DYLIB_PATH}" "$OUTPUT_DIR/"
    copied="true"
    ci_log "Captured iOS dylib from ${TIM2TOX_IOS_DYLIB_PATH}"
  fi

  if [[ "$copied" != "true" ]]; then
    ci_warn "No iOS Tim2Tox framework/dylib provided; iOS package will be produced unsigned and without injected Tim2Tox native binary"
  fi
}

case "$TARGET" in
  linux|windows|macos)
    build_desktop_target "$TARGET"
    ;;
  android)
    sync_android_ffi_libs
    ;;
  ios)
    sync_ios_ffi_artifacts
    ;;
  *)
    ci_die "Unsupported target: $TARGET"
    ;;
esac

ci_log "Done preparing Tim2Tox artifacts for $TARGET ($MODE)"
