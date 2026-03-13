#!/bin/bash

# Debug build script for toxee
# Builds the app in DEBUG mode and launches it once (no source watching, no auto-restart).

set -euo pipefail

# ============================================================
# Configuration
# ============================================================

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARENT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
TIM2TOX_DIR="$SCRIPT_DIR/third_party/tim2tox"
TIM2TOX_BUILD_DIR="$TIM2TOX_DIR/build"
TIM2TOX_EXAMPLE_BUILD_DIR="$TIM2TOX_DIR/example/build"
FFI_LIB="$TIM2TOX_BUILD_DIR/ffi/libtim2tox_ffi.dylib"
IRC_LIB="$TIM2TOX_EXAMPLE_BUILD_DIR/libirc_client.dylib"
FLUTTER_APP_DIR="$SCRIPT_DIR"
BUILD_DIR="$SCRIPT_DIR/build"
CLIENT_LOG="$BUILD_DIR/flutter_client.log"
NATIVE_BUILD_LOG="$BUILD_DIR/native_build.log"
FLUTTER_BUILD_LOG="$BUILD_DIR/flutter_build.log"
APP_BUNDLE="$FLUTTER_APP_DIR/build/macos/Build/Products/Debug/Toxee.app"
APP_EXE_DIR="$APP_BUNDLE/Contents/MacOS"
APP_EXECUTABLE="$APP_EXE_DIR/Toxee"
APP_SUPPORT_LOG="$HOME/Library/Containers/com.example.toxee/Data/Library/Application Support/com.example.toxee/flutter_client.log"

mkdir -p "$BUILD_DIR"

# Bootstrap dependencies so pubspec_overrides and third_party are ready
(cd "$FLUTTER_APP_DIR" && dart run tool/bootstrap_deps.dart) >> "$BUILD_DIR/bootstrap.log" 2>&1 || true

# Process IDs
APP_PID=""
TAIL_PID=""

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# ============================================================
# Cleanup
# ============================================================

cleanup() {
  local pids=("$TAIL_PID" "$APP_PID")
  for pid in "${pids[@]}"; do
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
    fi
  done
}
trap cleanup EXIT INT TERM

# ============================================================
# Helper functions
# ============================================================

# Run cmake configure with standard debug flags
cmake_configure() {
  local build_dir="$1" source_dir="$2"
  shift 2
  (cd "$build_dir" && cmake "$source_dir" \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_CXX_FLAGS_DEBUG="-g -O0" \
    -DCMAKE_C_FLAGS_DEBUG="-g -O0" \
    "$@") >> "$NATIVE_BUILD_LOG" 2>&1
}

# Find a Homebrew library file
find_brew_lib() {
  local pkg="$1" lib_name="$2"
  if [[ -n "${BREW_PREFIX_ROOT:-}" ]]; then
    local pkg_prefix
    pkg_prefix=$(brew --prefix "$pkg" 2>/dev/null || true)
    if [[ -n "$pkg_prefix" && -f "$pkg_prefix/lib/$lib_name" ]]; then
      echo "$pkg_prefix/lib/$lib_name"; return
    fi
  fi
  local path
  for path in "/opt/homebrew/opt/$pkg/lib/$lib_name" "/usr/local/opt/$pkg/lib/$lib_name"; do
    [[ -f "$path" ]] && { echo "$path"; return; }
  done
}

# Bundle a dylib dependency into the app and rewrite install_name
bundle_dylib() {
  local dylib_in_bundle="$1" dep_pattern="$2" brew_pkg="$3"
  local extra_search="${4:-}"

  local dep_old
  dep_old=$(otool -L "$dylib_in_bundle" | awk "/$dep_pattern/ {print \$1; exit}" || true)
  [[ -z "$dep_old" ]] && return 0

  local dep_name dep_src
  dep_name="$(basename "$dep_old")"
  dep_src=$(find_brew_lib "$brew_pkg" "$dep_name")

  if [[ -z "$dep_src" && -n "$extra_search" && -f "$extra_search/$dep_name" ]]; then
    dep_src="$extra_search/$dep_name"
  fi
  if [[ -z "$dep_src" || ! -f "$dep_src" ]]; then
    echo -e "${YELLOW}Warning: Could not find $dep_name${NC}"; return 0
  fi

  chmod +w "$APP_EXE_DIR/$dep_name" 2>/dev/null || true
  rm -f "$APP_EXE_DIR/$dep_name" 2>/dev/null || true
  cp "$dep_src" "$APP_EXE_DIR/" || { echo -e "${YELLOW}Warning: Failed to copy $dep_name${NC}"; return 0; }

  install_name_tool -change "$dep_old" "@loader_path/$dep_name" "$dylib_in_bundle" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
  echo -e "${GREEN}  Bundled $dep_name${NC}"
}

# ============================================================
# Build functions
# ============================================================

build_native() {
  echo -e "${YELLOW}==> Building native libraries (DEBUG)...${NC}"
  mkdir -p "$TIM2TOX_BUILD_DIR" "$TIM2TOX_EXAMPLE_BUILD_DIR"
  : > "$NATIVE_BUILD_LOG"

  # Configure tim2tox if needed
  local cmake_ffi_args=(-DBUILD_FFI=ON -DBUILD_TOXAV=ON -DMUST_BUILD_TOXAV=ON -DDHT_BOOTSTRAP=ON -DBOOTSTRAP_DAEMON=ON)
  local needs_configure=false

  if [[ ! -f "$TIM2TOX_BUILD_DIR/CMakeCache.txt" ]] || \
     [[ "$TIM2TOX_DIR/CMakeLists.txt" -nt "$TIM2TOX_BUILD_DIR/CMakeCache.txt" ]]; then
    needs_configure=true
  elif ! grep -q "BUILD_TOXAV:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "MUST_BUILD_TOXAV:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "DHT_BOOTSTRAP:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null || \
       ! grep -q "BOOTSTRAP_DAEMON:BOOL=ON" "$TIM2TOX_BUILD_DIR/CMakeCache.txt" 2>/dev/null; then
    echo -e "${YELLOW}    Reconfiguring to enable required build options...${NC}"
    needs_configure=true
  fi
  if [[ "$needs_configure" == "true" ]]; then
    cmake_configure "$TIM2TOX_BUILD_DIR" "$TIM2TOX_DIR" "${cmake_ffi_args[@]}"
  fi
  (cd "$TIM2TOX_BUILD_DIR" && make -j"$(sysctl -n hw.ncpu)" tim2tox_ffi) >> "$NATIVE_BUILD_LOG" 2>&1

  # Build IRC client library
  if [[ ! -f "$TIM2TOX_EXAMPLE_BUILD_DIR/CMakeCache.txt" ]] || \
     [[ "$TIM2TOX_DIR/example/CMakeLists.txt" -nt "$TIM2TOX_EXAMPLE_BUILD_DIR/CMakeCache.txt" ]]; then
    cmake_configure "$TIM2TOX_EXAMPLE_BUILD_DIR" "$TIM2TOX_DIR/example"
  fi
  (cd "$TIM2TOX_EXAMPLE_BUILD_DIR" && make -j"$(sysctl -n hw.ncpu)" irc_client) >> "$NATIVE_BUILD_LOG" 2>&1

  # Verify
  for lib in "$FFI_LIB" "$IRC_LIB"; do
    if [[ ! -f "$lib" ]]; then
      echo -e "${RED}Build artifacts missing: $lib${NC}"; return 1
    fi
  done
  echo -e "${GREEN}    Native libraries built successfully.${NC}"
}

build_flutter() {
  : > "$FLUTTER_BUILD_LOG"

  # pub get if needed
  if [[ ! -f "$FLUTTER_APP_DIR/pubspec.lock" ]] || \
     [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$FLUTTER_APP_DIR/pubspec.lock" ]]; then
    (cd "$FLUTTER_APP_DIR" && flutter pub get) >> "$FLUTTER_BUILD_LOG" 2>&1
  fi

  # Ensure macOS project exists
  if [[ ! -d "$FLUTTER_APP_DIR/macos" ]]; then
    echo -e "${YELLOW}    Adding macOS desktop support...${NC}"
    (cd "$FLUTTER_APP_DIR" && flutter create . --platforms=macos) >> "$FLUTTER_BUILD_LOG" 2>&1
  fi

  # Determine build strategy
  local needs_clean=false
  if [[ ! -d "$APP_BUNDLE" ]] || [[ ! -f "$APP_EXECUTABLE" ]]; then
    needs_clean=true
  elif [[ "$FLUTTER_APP_DIR/pubspec.yaml" -nt "$APP_BUNDLE" ]]; then
    needs_clean=true
    echo -e "${YELLOW}    pubspec.yaml changed, cleaning...${NC}"
  fi

  if [[ "$needs_clean" == "true" ]]; then
    echo -e "${YELLOW}==> Clean Flutter build...${NC}"
    (cd "$FLUTTER_APP_DIR" && flutter clean) >> "$FLUTTER_BUILD_LOG" 2>&1
    rm -rf "$APP_BUNDLE" || true
    mkdir -p "$BUILD_DIR"
    : > "$FLUTTER_BUILD_LOG"
  fi

  echo -e "${YELLOW}==> Building Flutter app (DEBUG)...${NC}"
  (cd "$FLUTTER_APP_DIR" && flutter build macos --debug --dart-define=FLUTTER_BUILD_MODE=debug) >> "$FLUTTER_BUILD_LOG" 2>&1

  if [[ ! -d "$APP_EXE_DIR" ]]; then
    echo -e "${RED}macOS app bundle not found at ${APP_BUNDLE}${NC}"; return 1
  fi
  echo -e "${GREEN}    Built: $APP_BUNDLE${NC}"
}

bundle_libs() {
  echo -e "${YELLOW}==> Bundling native libraries...${NC}"
  cp "$FFI_LIB" "$APP_EXE_DIR/"
  cp "$IRC_LIB" "$APP_EXE_DIR/"

  local ffi_dylib="$APP_EXE_DIR/libtim2tox_ffi.dylib"
  local irc_dylib="$APP_EXE_DIR/libirc_client.dylib"

  # Bundle libsodium (needed by both FFI and IRC)
  local sodium_old
  sodium_old=$(otool -L "$ffi_dylib" | awk '/libsodium\..*dylib/ {print $1; exit}')
  [[ -z "$sodium_old" ]] && sodium_old=$(otool -L "$irc_dylib" | awk '/libsodium\..*dylib/ {print $1; exit}')
  if [[ -n "$sodium_old" ]]; then
    local sodium_name sodium_src
    sodium_name="$(basename "$sodium_old")"
    sodium_src=$(find_brew_lib "libsodium" "$sodium_name")
    [[ -z "$sodium_src" && -f "$TIM2TOX_BUILD_DIR/toxcore_build/$sodium_name" ]] && \
      sodium_src="$TIM2TOX_BUILD_DIR/toxcore_build/$sodium_name"
    if [[ -n "$sodium_src" && -f "$sodium_src" ]]; then
      chmod +w "$APP_EXE_DIR/$sodium_name" 2>/dev/null || true
      rm -f "$APP_EXE_DIR/$sodium_name" 2>/dev/null || true
      cp "$sodium_src" "$APP_EXE_DIR/" || true
      install_name_tool -change "$sodium_old" "@loader_path/$sodium_name" "$ffi_dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
      install_name_tool -change "$sodium_old" "@loader_path/$sodium_name" "$irc_dylib" >> "$FLUTTER_BUILD_LOG" 2>&1 || true
      echo -e "${GREEN}  Bundled $sodium_name${NC}"
    fi
  fi

  # Bundle opus and vpx (toxav dependencies)
  bundle_dylib "$ffi_dylib" 'libopus\..*dylib' "opus"
  bundle_dylib "$ffi_dylib" 'libvpx\..*dylib'  "libvpx"
}

# ============================================================
# App lifecycle
# ============================================================

stop_app() {
  if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
    kill "$TAIL_PID" 2>/dev/null || true
    wait "$TAIL_PID" 2>/dev/null || true
    TAIL_PID=""
  fi
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" 2>/dev/null; then
    kill "$APP_PID" 2>/dev/null || true
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
  fi
}

launch_app() {
  export TIM2TOX_FFI_PATH="$FFI_LIB"
  export DYLD_FALLBACK_LIBRARY_PATH="$APP_EXE_DIR:${DYLD_FALLBACK_LIBRARY_PATH:-}"
  export TOXEE_LOG_DIR="$FLUTTER_APP_DIR/build"

  # Clear log files; ensure App Support log dir exists (sandbox path may not exist yet)
  : > "$CLIENT_LOG"
  mkdir -p "$(dirname "$APP_SUPPORT_LOG")"
  : > "$APP_SUPPORT_LOG"

  echo -e "${YELLOW}==> Launching app (DEBUG)...${NC}"
  "$APP_EXECUTABLE" >> "$APP_SUPPORT_LOG" 2>&1 &
  APP_PID=$!

  sleep 2

  # Symlink log for convenience
  if [[ -f "$APP_SUPPORT_LOG" ]]; then
    rm -f "$CLIENT_LOG"
    ln -s "$APP_SUPPORT_LOG" "$CLIENT_LOG" 2>/dev/null || \
      cp "$APP_SUPPORT_LOG" "$CLIENT_LOG" 2>/dev/null || true
  fi

  # Bring window to front
  sleep 1
  osascript -e 'tell application "System Events" to set frontmost of process "Toxee" to true' >/dev/null 2>&1 || true

  # Start tailing log
  local tail_log="$CLIENT_LOG"
  [[ -f "$APP_SUPPORT_LOG" ]] && tail_log="$APP_SUPPORT_LOG"
  tail -f "$tail_log" &
  TAIL_PID=$!

  echo ""
  echo -e "${GREEN}Logs:${NC}"
  echo "  Native build: $NATIVE_BUILD_LOG"
  echo "  Flutter build: $FLUTTER_BUILD_LOG"
  echo "  Client:        $CLIENT_LOG"
  echo ""
  echo -e "${YELLOW}  Debugger:     lldb -p $APP_PID${NC}"
  echo -e "${YELLOW}  Symbolicate:  atos -arch arm64 -o $APP_EXECUTABLE -l <load_addr> <crash_addr>${NC}"
  echo ""
}

# ============================================================
# Main
# ============================================================

# Set up Homebrew paths
BREW_PREFIX_ROOT=""
if command -v brew >/dev/null 2>&1; then
  BREW_PREFIX_ROOT=$(brew --prefix)
  export PKG_CONFIG_PATH="${BREW_PREFIX_ROOT}/opt/opus/lib/pkgconfig:${BREW_PREFIX_ROOT}/opt/libvpx/lib/pkgconfig:${BREW_PREFIX_ROOT}/opt/libconfig/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export CMAKE_PREFIX_PATH="${BREW_PREFIX_ROOT}/opt/opus:${BREW_PREFIX_ROOT}/opt/libvpx:${BREW_PREFIX_ROOT}/opt/libconfig:${CMAKE_PREFIX_PATH:-}"
fi

# Preflight checks
if [[ ! -f "$FLUTTER_APP_DIR/pubspec.yaml" ]]; then
  echo -e "${RED}Flutter app not found at ${FLUTTER_APP_DIR}${NC}"; exit 1
fi
if ! command -v flutter >/dev/null 2>&1; then
  echo -e "${RED}Flutter is not installed or not in PATH.${NC}"
  echo "Please install Flutter SDK and ensure 'flutter' is in PATH, then re-run."
  exit 1
fi

echo -e "${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  Toxee — DEBUG Build                 ║${NC}"
echo -e "${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# Build native, Flutter, bundle libs, launch once
build_native

if ! build_flutter; then
  echo -e "${RED}==> Flutter build failed! Check: $FLUTTER_BUILD_LOG${NC}"
  exit 1
fi
bundle_libs
launch_app

# Wait for app to exit (no source watching)
wait "$APP_PID" 2>/dev/null || true
APP_EXIT=$?
APP_PID=""

# Stop tail
if [[ -n "$TAIL_PID" ]] && kill -0 "$TAIL_PID" 2>/dev/null; then
  kill "$TAIL_PID" 2>/dev/null || true
  wait "$TAIL_PID" 2>/dev/null || true
  TAIL_PID=""
fi

echo ""
if [[ "$APP_EXIT" -eq 0 ]]; then
  echo -e "${GREEN}==> App exited normally (code 0).${NC}"
else
  echo -e "${RED}==> App exited with code $APP_EXIT.${NC}"
fi
exit "${APP_EXIT:-0}"
