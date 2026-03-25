#!/usr/bin/env bash

set -euo pipefail

ci_log() {
  printf '[ci] %s\n' "$*"
}

ci_warn() {
  printf '[ci][warn] %s\n' "$*" >&2
}

ci_die() {
  printf '[ci][error] %s\n' "$*" >&2
  exit 1
}

ci_require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || ci_die "Missing required command: $cmd"
}

ci_repo_root() {
  local dir
  dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
  printf '%s\n' "$dir"
}

ci_host_os() {
  if [[ -n "${RUNNER_OS:-}" ]]; then
    printf '%s\n' "${RUNNER_OS,,}"
    return
  fi

  case "$(uname -s)" in
    Darwin) printf '%s\n' "macos" ;;
    Linux) printf '%s\n' "linux" ;;
    MINGW*|MSYS*|CYGWIN*) printf '%s\n' "windows" ;;
    *) printf '%s\n' "unknown" ;;
  esac
}

ci_cpu_count() {
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return
  fi

  if command -v sysctl >/dev/null 2>&1; then
    sysctl -n hw.ncpu
    return
  fi

  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
    return
  fi

  printf '%s\n' "4"
}

ci_mode_dirname() {
  case "$1" in
    debug) printf '%s\n' "Debug" ;;
    profile) printf '%s\n' "Profile" ;;
    release) printf '%s\n' "Release" ;;
    *) ci_die "Unknown build mode: $1" ;;
  esac
}

ci_windows_path() {
  local path="$1"
  if command -v cygpath >/dev/null 2>&1; then
    cygpath -m "$path"
  else
    printf '%s\n' "$path"
  fi
}

ci_reset_dir() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
}

ci_copy_matching_file() {
  local search_root="$1"
  local pattern="$2"
  local destination_dir="$3"
  local match

  match="$(find "$search_root" -type f -name "$pattern" | head -n 1 || true)"
  if [[ -n "$match" ]]; then
    mkdir -p "$destination_dir"
    cp "$match" "$destination_dir/"
    printf '%s\n' "$match"
    return 0
  fi

  return 1
}

ci_sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return
  fi

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return
  fi

  ci_die "Missing sha256 tool"
}
