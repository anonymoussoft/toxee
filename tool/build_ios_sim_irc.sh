#!/bin/bash
#
# build_ios_sim_irc.sh — cross-compile libirc_client (the on-demand IRC
# application library) for the iOS Simulator.
#
# The IRC library has only ever been produced for macOS: run_toxee.sh runs
# `make irc_client` in the tim2tox example build dir and copies the Homebrew-
# linked libirc_client.dylib next to the app executable. That binary cannot
# load on an iOS simulator (wrong Mach-O platform, and it dynamically links
# /opt/homebrew OpenSSL), so lib/util/irc_app_manager.dart's
# `nativeLibraryProbe()` reports `available: false` on iOS and the real-UI
# `irc_join_channel_loopback_live` case SKIPs there. This script is the
# missing artifact producer — the IRC counterpart of tool/build_ios_sim_ffi.sh
# and it mirrors that script's conventions exactly (xcrun SDK path, IOS_MIN,
# `-target <arch>-apple-ios<min>-simulator`, per-arch build/cache dirs under
# third_party/tim2tox/build/ios-sim-<arch>/, lipo, `codesign -s -`).
#
# What it builds, per arch:
#   * OpenSSL (static libssl.a + libcrypto.a) from the pinned release tarball,
#     cached in the SAME deps-prefix build_ios_sim_ffi.sh uses for libsodium /
#     opus / vpx (third_party/tim2tox/build/ios-sim-<arch>/deps-prefix). The
#     IRC sources need it unconditionally (<openssl/ssl.h>, SSL_* for the
#     use_ssl=1 path); nothing else on the simulator provides one. Configured
#     minimal (no apps/tests/docs/engines/modules/asm/QUIC) so the build is a
#     couple of minutes per arch instead of ten. `deprecated` is deliberately
#     NOT disabled: IrcClientManager.cpp calls SSL_library_init().
#   * libirc_client.dylib from the same three sources every desktop build uses
#     (source/irc_client_api.cpp, source/IrcClientManager.cpp) plus
#     source/V2TIMLog.cpp — the only tim2tox symbol the IRC code needs. The
#     desktop graphs (example/CMakeLists.txt, ffi/CMakeLists.txt with
#     -DTIM2TOX_BUILD_IRC=ON) satisfy that by linking the whole tim2tox static
#     library, which pulls in toxcore/sodium/opus/vpx for nothing and would
#     force a full tim2tox rebuild in a fresh build dir. Compiling V2TIMLog.cpp
#     directly keeps the library self-contained (its own V2TIMLog singleton,
#     exactly like the macOS build where the static link already gives it a
#     private copy). The tiny CMake project is generated under the build dir
#     so the tim2tox submodule is not modified.
#   * a UNIVERSAL (arm64 + x86_64) simulator dylib by default, for the same
#     reason as the FFI: several pods lack an arm64-simulator slice, so the
#     Runner builds x86_64 (Rosetta) on Apple Silicon.
#
# Output (SDK=iphonesimulator, the default):
#   third_party/tim2tox/build/ios-sim/libirc_client.dylib   (universal,
#       install_name @rpath/libirc_client.dylib, ad-hoc signed)
# Output (SDK=iphoneos — real device):
#   third_party/tim2tox/build/ios-dev/libirc_client.dylib   (arm64)
#
# This script only PRODUCES the artifact. run_toxee_ios.sh's deploy step
# (inject_ios_ffi_artifacts) copies it to Runner.app/Frameworks/ — the path
# irc_app_manager.dart probes on iOS — and removes a stale copy when the
# artifact is absent, so the live IRC case SKIPs honestly without it.
#
# Env overrides: ARCHS (default "arm64 x86_64" sim / "arm64" device),
#                SDK (iphonesimulator|iphoneos), IOS_MIN (default 13.0),
#                OPENSSL_VERSION / OPENSSL_SHA256 (pinned below),
#                JOBS (default hw.ncpu).
# On a busy Mac, run it under `taskpolicy -b bash tool/build_ios_sim_irc.sh`
# to confine the OpenSSL compile to the efficiency cores.
set -euo pipefail

SDK="${SDK:-iphonesimulator}"
if [[ "$SDK" == iphoneos* ]]; then
  ARCHS="${ARCHS:-arm64}"
  VARIANT="ios-dev"
  [[ "$ARCHS" == "arm64" ]] || { echo "SDK=iphoneos supports only ARCHS=arm64 (got '$ARCHS')" >&2; exit 1; }
else
  ARCHS="${ARCHS:-arm64 x86_64}"
  VARIANT="ios-sim"
fi
IOS_MIN="${IOS_MIN:-13.0}"
# Pinned to the release Homebrew ships on the macOS side (openssl@3 3.6.2) so
# the simulator library talks the same OpenSSL as the desktop one. SHA-256
# cross-checked against the official `.sha256` sidecar of the GitHub release
# asset (2026-09-05).
OPENSSL_VERSION="${OPENSSL_VERSION:-3.6.2}"
OPENSSL_SHA256="${OPENSSL_SHA256:-aaf51a1fe064384f811daeaeb4ec4dce7340ec8bd893027eee676af31e83a04f}"
JOBS="${JOBS:-$(sysctl -n hw.ncpu 2>/dev/null || echo 4)}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; NC='\033[0m'
# All logging goes to stderr so function stdout (captured via $(...)) stays clean.
info() { echo -e "${GREEN}[ios-irc]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[ios-irc]${NC} $*" >&2; }
err()  { echo -e "${RED}[ios-irc]${NC} $*" >&2; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TIM2TOX_DIR="$REPO_ROOT/third_party/tim2tox"
DOWNLOADS="$TIM2TOX_DIR/build/mobile-deps/downloads"

[[ "$OSTYPE" == darwin* ]] || { err "macOS only"; exit 1; }
for t in cmake xcrun lipo codesign perl shasum; do
  command -v "$t" >/dev/null || { err "$t missing"; exit 1; }
done
for f in source/irc_client_api.cpp source/IrcClientManager.cpp source/V2TIMLog.cpp include/irc_client_api.h; do
  [[ -f "$TIM2TOX_DIR/$f" ]] || { err "tim2tox submodule not populated (missing $f)"; exit 1; }
done

SYSROOT="$(xcrun --sdk "$SDK" --show-sdk-path)"

triple_for() {
  local arch="$1"
  if [[ "$SDK" == "iphonesimulator" ]]; then echo "${arch}-apple-ios${IOS_MIN}-simulator";
  else echo "${arch}-apple-ios${IOS_MIN}"; fi
}
# OpenSSL Configure target (Configurations/15-ios.conf). Each one already sets
# CC to `xcrun -sdk <sdk> cc` and the matching `-arch`; the deployment target
# comes from the -target triple we append as a compiler flag.
openssl_target_for() {
  local arch="$1"
  if [[ "$SDK" == "iphonesimulator" ]]; then
    case "$arch" in
      arm64)  echo "iossimulator-arm64-xcrun" ;;
      x86_64) echo "iossimulator-x86_64-xcrun" ;;
      *) err "unsupported simulator arch '$arch'"; exit 1 ;;
    esac
  else
    case "$arch" in
      arm64) echo "ios64-xcrun" ;;
      *) err "unsupported device arch '$arch'"; exit 1 ;;
    esac
  fi
}

# Fetch + verify the OpenSSL release tarball once (shared downloads cache,
# same dir tool/ci/build_av_deps.sh uses for opus/vpx). A checksum mismatch
# is fatal and removes the file — never build from an unverified tarball.
fetch_openssl_tarball() {
  local tarball="$DOWNLOADS/openssl-${OPENSSL_VERSION}.tar.gz"
  mkdir -p "$DOWNLOADS"
  if [[ -f "$tarball" ]]; then
    local have; have="$(shasum -a 256 "$tarball" | awk '{print $1}')"
    if [[ "$have" == "$OPENSSL_SHA256" ]]; then
      echo "$tarball"; return 0
    fi
    warn "cached $(basename "$tarball") checksum mismatch ($have) — re-downloading"
    rm -f "$tarball"
  fi
  local urls=(
    "https://github.com/openssl/openssl/releases/download/openssl-${OPENSSL_VERSION}/openssl-${OPENSSL_VERSION}.tar.gz"
    "https://www.openssl.org/source/openssl-${OPENSSL_VERSION}.tar.gz"
  )
  local u ok=0
  for u in "${urls[@]}"; do
    info "downloading $u ..."
    if curl -fLsS --retry 3 --retry-delay 2 --connect-timeout 30 -o "$tarball.part" "$u"; then
      local have; have="$(shasum -a 256 "$tarball.part" | awk '{print $1}')"
      if [[ "$have" == "$OPENSSL_SHA256" ]]; then
        mv "$tarball.part" "$tarball"; ok=1; break
      fi
      err "checksum mismatch for $u: got $have, want $OPENSSL_SHA256"
    fi
    rm -f "$tarball.part"
  done
  [[ "$ok" == 1 ]] || { err "OpenSSL ${OPENSSL_VERSION} download failed"; exit 1; }
  echo "$tarball"
}

# Static OpenSSL for one arch into its deps-prefix (idempotent).
build_openssl() {
  local arch="$1" dep_prefix="$2" base="$3"
  if [[ -f "$dep_prefix/lib/libssl.a" && -f "$dep_prefix/lib/libcrypto.a" && -f "$dep_prefix/include/openssl/ssl.h" ]]; then
    info "[$arch] OpenSSL cached in $dep_prefix"
    return 0
  fi
  local tarball; tarball="$(fetch_openssl_tarball)"
  local target; target="$(openssl_target_for "$arch")"
  # Configure treats every leading-dash argument as ONE compiler flag and any
  # bare word as a target name, so the deployment target / sysroot must be
  # single tokens: `-target <triple>` would be read as flag + second target.
  # The Configure target already contributes the matching `-arch`, and with a
  # -m*-version-min flag clang derives the same <arch>-apple-ios<min>[-simulator]
  # triple the FFI build uses.
  local minflag
  if [[ "$SDK" == "iphonesimulator" ]]; then minflag="-mios-simulator-version-min=$IOS_MIN";
  else minflag="-miphoneos-version-min=$IOS_MIN"; fi
  local work="$base/src/openssl-extract"
  info "[$arch] building OpenSSL $OPENSSL_VERSION ($target) ..."
  rm -rf "$work" && mkdir -p "$work"
  tar xzf "$tarball" -C "$work"
  local sdir="$work/openssl-${OPENSSL_VERSION}"
  [[ -f "$sdir/Configure" ]] || { err "[$arch] unexpected tarball layout (no $sdir/Configure)"; exit 1; }
  ( cd "$sdir"
    # Minimal static build: libssl + libcrypto only. `no-deprecated` must stay
    # OFF (SSL_library_init). --openssldir is pinned inside the prefix so the
    # static library never looks at a host path at runtime.
    perl ./Configure "$target" \
      --prefix="$dep_prefix" --libdir=lib --openssldir="$dep_prefix/ssl" \
      no-shared no-tests no-apps no-docs no-dso no-engine no-module no-legacy \
      no-asm no-comp no-ui-console no-quic no-makedepend \
      "$minflag" "-isysroot$SYSROOT" \
      >"$base/openssl-configure.log" 2>&1 \
      || { err "[$arch] OpenSSL configure failed"; tail -25 "$base/openssl-configure.log" >&2; exit 1; }
    make -j"$JOBS" build_libs >"$base/openssl-make.log" 2>&1 \
      || { err "[$arch] OpenSSL build failed"; tail -35 "$base/openssl-make.log" >&2; exit 1; }
    make install_dev >>"$base/openssl-make.log" 2>&1 \
      || { err "[$arch] OpenSSL install_dev failed"; tail -25 "$base/openssl-make.log" >&2; exit 1; }
  ) || exit 1
  [[ -f "$dep_prefix/lib/libssl.a" && -f "$dep_prefix/lib/libcrypto.a" ]] \
    || { err "[$arch] OpenSSL install produced no static libs in $dep_prefix/lib"; exit 1; }
  rm -rf "$work"
}

# The CMake project for the library itself. Generated (not checked into the
# submodule) — see the header for why it compiles V2TIMLog.cpp directly.
write_cmake_project() {
  local dir="$1"
  mkdir -p "$dir"
  cat > "$dir/CMakeLists.txt" <<'CMAKE'
# Generated by tool/build_ios_sim_irc.sh — do not edit; edit the script.
cmake_minimum_required(VERSION 3.13)
project(tim2tox_irc_client CXX)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(TIM2TOX_ROOT "" CACHE PATH "tim2tox checkout (source/, include/)")
if(NOT EXISTS "${TIM2TOX_ROOT}/source/IrcClientManager.cpp")
    message(FATAL_ERROR "TIM2TOX_ROOT does not point at a tim2tox checkout: '${TIM2TOX_ROOT}'")
endif()
set(OPENSSL_USE_STATIC_LIBS TRUE)
find_package(OpenSSL REQUIRED)
add_library(irc_client SHARED
    ${TIM2TOX_ROOT}/source/irc_client_api.cpp
    ${TIM2TOX_ROOT}/source/IrcClientManager.cpp
    ${TIM2TOX_ROOT}/source/V2TIMLog.cpp
)
target_include_directories(irc_client PRIVATE
    ${TIM2TOX_ROOT}/include
    ${TIM2TOX_ROOT}/source
)
target_link_libraries(irc_client PRIVATE OpenSSL::SSL OpenSSL::Crypto)
set_target_properties(irc_client PROPERTIES
    OUTPUT_NAME "irc_client"
    PREFIX "lib"
    POSITION_INDEPENDENT_CODE ON
    BUILD_WITH_INSTALL_NAME_DIR ON
    INSTALL_NAME_DIR "@rpath"
)
CMAKE
}

# Build OpenSSL + libirc_client for one arch; echoes the dylib path.
build_arch() {
  local arch="$1"
  local triple; triple="$(triple_for "$arch")"
  local base="$TIM2TOX_DIR/build/${VARIANT}-${arch}"
  local dep_prefix="$base/deps-prefix"
  local irc_build="$base/irc-build"
  mkdir -p "$base/src"

  build_openssl "$arch" "$dep_prefix" "$base"

  info "[$arch] configuring + building irc_client ..."
  # OPENSSL_ROOT_DIR pins find_package to the per-arch prefix; a stray Homebrew
  # (macOS) OpenSSL would otherwise satisfy it and the link would fail late or,
  # worse, produce a dylib that dlopen rejects on the simulator.
  cmake -S "$CMAKE_PROJECT_DIR" -B "$irc_build" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_OSX_SYSROOT="$SYSROOT" \
    -DCMAKE_OSX_ARCHITECTURES="$arch" \
    -DCMAKE_C_FLAGS="-target $triple" \
    -DCMAKE_CXX_FLAGS="-target $triple" \
    -DCMAKE_SHARED_LINKER_FLAGS="-target $triple" \
    -DTIM2TOX_ROOT="$TIM2TOX_DIR" \
    -DOPENSSL_ROOT_DIR="$dep_prefix" \
    -DCMAKE_PREFIX_PATH="$dep_prefix" \
    >"$base/irc-cmake-configure.log" 2>&1 || { err "[$arch] cmake configure failed"; tail -25 "$base/irc-cmake-configure.log" >&2; exit 1; }
  cmake --build "$irc_build" --target irc_client -j"$JOBS" \
    >"$base/irc-cmake-build.log" 2>&1 || { err "[$arch] cmake build failed"; tail -35 "$base/irc-cmake-build.log" >&2; exit 1; }

  local dy="$irc_build/libirc_client.dylib"
  [[ -f "$dy" ]] || { err "[$arch] no libirc_client.dylib produced"; exit 1; }
  echo "$dy"
}

OUT_BASE="$TIM2TOX_DIR/build/$VARIANT"
CMAKE_PROJECT_DIR="$OUT_BASE/irc-cmake"
mkdir -p "$OUT_BASE"
write_cmake_project "$CMAKE_PROJECT_DIR"

info "ARCHS='$ARCHS'  sdk=$SYSROOT  jobs=$JOBS"
SLICES=()
for a in $ARCHS; do
  dy="$(build_arch "$a")"
  info "[$a] built: $dy"
  SLICES+=("$dy")
done
[[ ${#SLICES[@]} -gt 0 ]] || { err "no arch slices built (ARCHS='$ARCHS' empty?)"; exit 1; }

# ---------------------------------------------------------------------------
# lipo into a single universal dylib
# ---------------------------------------------------------------------------
UNIVERSAL="$OUT_BASE/libirc_client.dylib"
if [[ ${#SLICES[@]} -gt 1 ]]; then
  lipo -create "${SLICES[@]}" -output "$UNIVERSAL"
else
  cp "${SLICES[0]}" "$UNIVERSAL"
fi
install_name_tool -id "@rpath/libirc_client.dylib" "$UNIVERSAL"

# ---------------------------------------------------------------------------
# Verify Mach-O platform / arch / exports / link set, then ad-hoc sign
# ---------------------------------------------------------------------------
echo -e "${CYAN}--- verification ---${NC}"
file "$UNIVERSAL"
lipo -info "$UNIVERSAL" || true
build_ver="$(vtool -show-build "$UNIVERSAL" 2>/dev/null || true)"
echo "build-version:"; grep -iE "platform|minos" <<<"$build_ver" | head
if [[ "$SDK" == "iphonesimulator" && "$build_ver" != *IOSSIMULATOR* ]]; then
  err "not an iOS-simulator Mach-O (LC_BUILD_VERSION platform mismatch)"; exit 1
fi
# The C API the Dart side resolves (irc_client_*). Captured symbol table — no
# `nm | grep -q` pipeline (grep -q's early exit SIGPIPEs nm under pipefail).
univ_syms="$(nm -g "$UNIVERSAL" 2>/dev/null || true)"
for s in _irc_client_init _irc_client_connect_channel _irc_client_send_message _irc_client_set_message_callback; do
  if [[ "$univ_syms" == *"$s"* ]]; then info "export present: $s"
  else err "export MISSING: $s"; exit 1; fi
done
# The only shared-library dependencies may be the iOS system ones (libc++,
# libSystem). Any /opt/homebrew or /usr/local path means a macOS OpenSSL leaked
# into the link and the dylib would never load on the simulator.
link_set="$(otool -L "$UNIVERSAL" | tail -n +2)"
echo "link set:"; echo "$link_set"
if grep -qE '/opt/homebrew|/usr/local' <<<"$link_set"; then
  err "host (macOS) library in link set — refusing to ship"; exit 1
fi

# dlopen'd from the app bundle: a bad signature is a hard failure on the
# simulator loader, so abort instead of warning.
codesign --force --sign - "$UNIVERSAL" || { err "codesign dylib failed"; exit 1; }
codesign --verify --strict "$UNIVERSAL" || { err "codesign --verify failed for dylib"; exit 1; }

info "Dylib: $UNIVERSAL"
echo -e "${GREEN}[ios-irc] DONE${NC}"
