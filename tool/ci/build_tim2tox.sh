#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=tool/ci/common.sh
source "$SCRIPT_DIR/common.sh"

TARGET=""
MODE="release"
WINDOWS_ARCH="${TIM2TOX_WINDOWS_ARCH:-x64}" # x64|arm64

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

find_android_ndk() {
  local candidate sdk_root latest

  for candidate in "${ANDROID_NDK_HOME:-}" "${ANDROID_NDK_ROOT:-}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  for sdk_root in "${ANDROID_SDK_ROOT:-}" "${ANDROID_HOME:-}"; do
    [[ -n "$sdk_root" && -d "$sdk_root" ]] || continue

    if [[ -d "$sdk_root/ndk" ]]; then
      latest="$(find "$sdk_root/ndk" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -n 1 || true)"
      if [[ -n "$latest" ]]; then
        printf '%s\n' "$latest"
        return
      fi
    fi

    if [[ -d "$sdk_root/ndk-bundle" ]]; then
      printf '%s\n' "$sdk_root/ndk-bundle"
      return
    fi
  done

  ci_die "Unable to locate Android NDK (checked ANDROID_NDK_HOME, ANDROID_NDK_ROOT, ANDROID_SDK_ROOT, ANDROID_HOME)"
}

download_file_once() {
  local url="$1"
  local dest="$2"

  if [[ ! -f "$dest" ]]; then
    if command -v curl >/dev/null 2>&1; then
      curl -L --fail --retry 3 --retry-delay 2 -o "$dest" "$url"
    elif command -v wget >/dev/null 2>&1; then
      wget -O "$dest" "$url"
    else
      ci_die "Missing curl/wget for downloading $url"
    fi
  fi
}

prepare_android_libsodium_prefix() {
  local abi="$1"
  local ndk_path="$2"
  local prefix="$TIM2TOX_DIR/build/mobile-deps/android-$abi"
  local download_dir="$TIM2TOX_DIR/build/mobile-deps/downloads"
  local src_root="$TIM2TOX_DIR/build/mobile-deps/src-android-$abi"
  local archive="$download_dir/libsodium-1.0.20.tar.gz"
  local host target api toolchain sysroot

  if [[ -f "$prefix/lib/libsodium.a" ]]; then
    return
  fi

  case "$abi" in
    arm64-v8a)
      target="aarch64-linux-android"
      api="21"
      ;;
    armeabi-v7a)
      target="armv7a-linux-androideabi"
      api="21"
      ;;
    x86_64)
      target="x86_64-linux-android"
      api="21"
      ;;
    *)
      ci_die "Unsupported Android ABI: $abi"
      ;;
  esac

  toolchain="$ndk_path/toolchains/llvm/prebuilt/linux-x86_64"
  sysroot="$toolchain/sysroot"

  mkdir -p "$download_dir"
  download_file_once \
    "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz" \
    "$archive"

  rm -rf "$src_root"
  mkdir -p "$src_root"
  tar -xzf "$archive" -C "$src_root"

  pushd "$src_root/libsodium-1.0.20" >/dev/null
  export CC="$toolchain/bin/${target}${api}-clang"
  export CXX="$toolchain/bin/${target}${api}-clang++"
  export AR="$toolchain/bin/llvm-ar"
  export RANLIB="$toolchain/bin/llvm-ranlib"
  export STRIP="$toolchain/bin/llvm-strip"
  ./configure \
    --prefix="$prefix" \
    --host="$target" \
    --with-sysroot="$sysroot" \
    --disable-shared \
    --disable-pie
  make -j"$(ci_cpu_count)"
  make install
  popd >/dev/null
}

android_libsodium_prefix_path() {
  printf '%s\n' "$TIM2TOX_DIR/build/mobile-deps/android-$1"
}

build_android_ffi_for_abi() {
  local abi="$1"
  local ndk_path="$2"
  local prefix build_dir built_lib repo_jni_libs toolchain sysroot

  prefix="$(android_libsodium_prefix_path "$abi")"
  prepare_android_libsodium_prefix "$abi" "$ndk_path"
  build_dir="$TIM2TOX_DIR/build/ci-android-$abi"
  repo_jni_libs="$REPO_ROOT/android/app/src/main/jniLibs"
  toolchain="$ndk_path/toolchains/llvm/prebuilt/linux-x86_64"
  sysroot="$toolchain/sysroot"

  mkdir -p "$OUTPUT_DIR/jniLibs/$abi"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"

  cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_TOOLCHAIN_FILE="$ndk_path/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="$abi" \
    -DANDROID_PLATFORM=21 \
    -DANDROID_STL=c++_shared \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DTIM2TOX_DEP_PREFIX="$prefix" \
    -DCMAKE_FIND_ROOT_PATH="$prefix;$sysroot" \
    -DCMAKE_C_FLAGS="-Wno-error=format" \
    -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-copy -Wno-error=format -DTIM2TOX_DISABLE_SQLITE=1" \
    "${configure_args[@]}"

  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name 'libtim2tox_ffi.so' | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate Android libtim2tox_ffi.so for ABI $abi"
  cp "$built_lib" "$OUTPUT_DIR/jniLibs/$abi/libtim2tox_ffi.so"
  ci_log "Captured Android native library for $abi: $built_lib"

  rm -rf "$repo_jni_libs"
  mkdir -p "$repo_jni_libs"
  cp -R "$OUTPUT_DIR/jniLibs"/. "$repo_jni_libs/"
}

build_android_ffi_libs() {
  local source_dir="${TIM2TOX_ANDROID_LIB_DIR:-}"
  local repo_jni_libs="$REPO_ROOT/android/app/src/main/jniLibs"
  local ndk_path abi
  local -a android_abis=()

  if [[ -z "$source_dir" ]]; then
    if [[ -d "$repo_jni_libs" ]] && find "$repo_jni_libs" -type f -name "libtim2tox_ffi.so" | grep -q .; then
      source_dir="$repo_jni_libs"
    fi
  fi

  if [[ -n "$source_dir" ]]; then
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
    return
  fi

  ndk_path="$(find_android_ndk)"
  if [[ -n "${TIM2TOX_ANDROID_ABIS:-}" ]]; then
    # shellcheck disable=SC2206
    android_abis=(${TIM2TOX_ANDROID_ABIS//,/ })
  else
    android_abis=(arm64-v8a)
  fi

  for abi in "${android_abis[@]}"; do
    build_android_ffi_for_abi "$abi" "$ndk_path"
  done

  ci_log "Built Android Tim2Tox JNI libraries for: ${android_abis[*]}"
}

ios_dependency_prefix_path() {
  printf '%s\n' "$TIM2TOX_DIR/build/mobile-deps/ios-arm64"
}

prepare_ios_libsodium_prefix() {
  local prefix
  local download_dir="$TIM2TOX_DIR/build/mobile-deps/downloads"
  local src_root="$TIM2TOX_DIR/build/mobile-deps/src-ios-arm64"
  local archive="$download_dir/libsodium-1.0.20.tar.gz"
  local sdk_path host

  prefix="$(ios_dependency_prefix_path)"
  if [[ -f "$prefix/lib/libsodium.a" ]]; then
    return
  fi

  mkdir -p "$download_dir"
  download_file_once \
    "https://github.com/jedisct1/libsodium/releases/download/1.0.20-RELEASE/libsodium-1.0.20.tar.gz" \
    "$archive"

  rm -rf "$src_root"
  mkdir -p "$src_root"
  tar -xzf "$archive" -C "$src_root"

  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
  host="arm-apple-darwin"

  pushd "$src_root/libsodium-1.0.20" >/dev/null
  export CC="$(xcrun --sdk iphoneos --find clang)"
  export CXX="$(xcrun --sdk iphoneos --find clang++)"
  export AR="$(xcrun --sdk iphoneos --find ar)"
  export RANLIB="$(xcrun --sdk iphoneos --find ranlib)"
  export STRIP="$(xcrun --sdk iphoneos --find strip)"
  export CFLAGS="-arch arm64 -isysroot $sdk_path -miphoneos-version-min=13.0"
  export CXXFLAGS="$CFLAGS"
  export LDFLAGS="$CFLAGS"
  ./configure \
    --prefix="$prefix" \
    --host="$host" \
    --disable-shared \
    --disable-pie
  make -j"$(ci_cpu_count)"
  make install
  popd >/dev/null
}

build_ios_ffi_dylib() {
  local prefix build_dir sdk_path built_lib framework_dir

  prefix="$(ios_dependency_prefix_path)"
  prepare_ios_libsodium_prefix
  build_dir="$TIM2TOX_DIR/build/ci-ios-arm64"
  sdk_path="$(xcrun --sdk iphoneos --show-sdk-path)"
  export PKG_CONFIG_PATH="$prefix/lib/pkgconfig"

  cmake -S "$TIM2TOX_DIR" -B "$build_dir" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_C_COMPILER="$(xcrun --sdk iphoneos --find clang)" \
    -DCMAKE_CXX_COMPILER="$(xcrun --sdk iphoneos --find clang++)" \
    -DCMAKE_TRY_COMPILE_TARGET_TYPE=STATIC_LIBRARY \
    -DCMAKE_PREFIX_PATH="$prefix" \
    -DTIM2TOX_DEP_PREFIX="$prefix" \
    -DCMAKE_C_FLAGS="-miphoneos-version-min=13.0 -arch arm64 -Wno-error=format" \
    -DCMAKE_CXX_FLAGS="-miphoneos-version-min=13.0 -arch arm64 -Wno-error=deprecated-copy -Wno-error=format -DTIM2TOX_DISABLE_SQLITE=1" \
    -DCMAKE_EXE_LINKER_FLAGS="-miphoneos-version-min=13.0 -arch arm64" \
    -DCMAKE_SHARED_LINKER_FLAGS="-miphoneos-version-min=13.0 -arch arm64" \
    "${configure_args[@]}"

  cmake --build "$build_dir" --config Release --target tim2tox_ffi --parallel "$(ci_cpu_count)"

  built_lib="$(find "$build_dir" -type f -name 'libtim2tox_ffi.dylib' | head -n 1 || true)"
  [[ -n "$built_lib" ]] || ci_die "Failed to locate iOS libtim2tox_ffi.dylib"

  framework_dir="$OUTPUT_DIR/tim2tox_ffi.framework"
  rm -rf "$framework_dir"
  mkdir -p "$framework_dir"
  cp "$built_lib" "$framework_dir/tim2tox_ffi"
  cat > "$framework_dir/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>tim2tox_ffi</string>
  <key>CFBundleIdentifier</key>
  <string>org.toxee.tim2tox_ffi</string>
  <key>CFBundleName</key>
  <string>tim2tox_ffi</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>MinimumOSVersion</key>
  <string>13.0</string>
</dict>
</plist>
EOF
  ci_log "Captured iOS framework from $built_lib"
}

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
      local vs_arch vcpkg_triplet
      # bash 3.x on macOS doesn't support ${var,,} lowercase expansion.
      local windows_arch_lc
      windows_arch_lc="$(printf "%s" "${WINDOWS_ARCH}" | tr '[:upper:]' '[:lower:]')"
      case "${windows_arch_lc}" in
        arm64)
          vs_arch="arm64"
          vcpkg_triplet="arm64-windows"
          ;;
        x64|*)
          vs_arch="x64"
          vcpkg_triplet="x64-windows"
          ;;
      esac
      if [[ -n "${VCPKG_ROOT:-}" ]]; then
        local vcpkg_root_win toolchain_file
        vcpkg_root_win="$(ci_windows_path "$VCPKG_ROOT")"
        toolchain_file="${vcpkg_root_win}/scripts/buildsystems/vcpkg.cmake"
        # Ensure tools invoked by CMake/MSBuild are discoverable.
        # 1) pkg-config: used by FindPkgConfig during configure.
        export PATH="$VCPKG_ROOT/installed/$vcpkg_triplet/tools/pkgconf:$PATH"
        # 2) powershell.exe: used by vcpkg's applocal.ps1 post-build step.
        # Git Bash (MSYS) typically exposes it under /c/WINDOWS/...
        export PATH="/c/WINDOWS/System32/WindowsPowerShell/v1.0:$PATH"
        VCPKG_ROOT="$vcpkg_root_win" cmake -S "$source_dir_win" -B "$build_dir_win" \
          -G "Visual Studio 17 2022" -A "$vs_arch" \
          -DCMAKE_TOOLCHAIN_FILE="$toolchain_file" \
          "${configure_args[@]}"
      else
        cmake -S "$source_dir_win" -B "$build_dir_win" -G "Visual Studio 17 2022" -A "$vs_arch" "${configure_args[@]}"
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
    ci_copy_matching_file "$VCPKG_ROOT/installed/$vcpkg_triplet" "libsodium.dll" "$OUTPUT_DIR" >/dev/null || \
      ci_warn "libsodium.dll not found under $VCPKG_ROOT/installed/$vcpkg_triplet"
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
    build_ios_ffi_dylib
  fi
}

case "$TARGET" in
  linux|windows|macos)
    build_desktop_target "$TARGET"
    ;;
  android)
    build_android_ffi_libs
    ;;
  ios)
    sync_ios_ffi_artifacts
    ;;
  *)
    ci_die "Unsupported target: $TARGET"
    ;;
esac

ci_log "Done preparing Tim2Tox artifacts for $TARGET ($MODE)"
