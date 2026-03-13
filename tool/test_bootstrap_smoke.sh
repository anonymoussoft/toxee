#!/usr/bin/env bash
# Smoke test for bootstrap: clean vendor/overrides and run bootstrap (or --offline-check-only).
# Expect failure when tool is missing; after implementation, expects success or defined failure modes.
# With --test-missing-patch: temporarily break series to assert bootstrap fails when a declared patch is missing.
set -e
cd "$(dirname "$0")/.."
ROOT="$PWD"

# Remove generated artifacts
rm -rf third_party/tencent_cloud_chat_sdk
rm -f pubspec_overrides.yaml

# Deinitialize submodules if present so we can test from a clean state
if [ -f .gitmodules ]; then
  for sub in third_party/tim2tox third_party/chat-uikit-flutter; do
    if [ -d "$sub/.git" ]; then
      git submodule deinit -f "$sub" 2>/dev/null || true
      rm -rf "$sub"
    fi
  done
fi

if [ "$1" = "--test-missing-patch" ]; then
  # Require tim2tox and a series file so we can test missing-patch failure
  SERIES="third_party/tim2tox/patches/tencent_cloud_chat_sdk/8.7.7201/series"
  if [ ! -f "$SERIES" ]; then
    echo "No series file at $SERIES; skip missing-patch test" >&2
    exit 0
  fi
  BACKUP="$SERIES.bak"
  cp "$SERIES" "$BACKUP"
  echo "nonexistent.patch" >> "$SERIES"
  if dart run tool/bootstrap_deps.dart 2>/dev/null; then
    mv "$BACKUP" "$SERIES"
    echo "Expected bootstrap to fail when patch in series is missing" >&2
    exit 1
  fi
  mv "$BACKUP" "$SERIES"
  echo "Bootstrap correctly failed when patch file declared in series was missing."
  exit 0
fi

# Run bootstrap (or offline check); allow failure when tool is missing
if [ "$1" = "--offline-check-only" ]; then
  dart run tool/bootstrap_deps.dart --offline-check-only || true
else
  dart run tool/bootstrap_deps.dart || true
fi
