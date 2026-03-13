#!/usr/bin/env bash
# Regenerate tencent_cloud_chat_sdk patches from local edits in third_party/tencent_cloud_chat_sdk
# and write them into third_party/tim2tox/patches/tencent_cloud_chat_sdk/<version>/.
# Run from toxee repo root. Requires lock file for version.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK_DIR="$ROOT/third_party/tencent_cloud_chat_sdk"
TIM2TOX="$ROOT/third_party/tim2tox"
LOCK="$ROOT/third_party/tim2tox/tool/tencent_cloud_chat_sdk.lock.json"

if [ ! -f "$LOCK" ]; then
  echo "Missing $LOCK" >&2
  exit 1
fi
VERSION=$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$LOCK" | head -1)
if [ -z "$VERSION" ]; then
  echo "Could not read version from lock file" >&2
  exit 1
fi
PATCHES_DIR="$TIM2TOX/patches/tencent_cloud_chat_sdk/$VERSION"
if [ ! -d "$SDK_DIR" ]; then
  echo "SDK dir not found: $SDK_DIR (run bootstrap first)" >&2
  exit 1
fi
if [ ! -d "$TIM2TOX" ]; then
  echo "tim2tox not found: $TIM2TOX (run bootstrap first)" >&2
  exit 1
fi

mkdir -p "$PATCHES_DIR"
cd "$SDK_DIR"
# Generate patch from working tree (and staged) vs HEAD. If not a git repo, we could use diff of dir.
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git diff HEAD -- . > "$PATCHES_DIR/0001-local.patch" || true
  if [ ! -s "$PATCHES_DIR/0001-local.patch" ]; then
    rm -f "$PATCHES_DIR/0001-local.patch"
    echo "No local changes in SDK dir; no patch written."
    exit 0
  fi
else
  echo "SDK dir is not a git repo; cannot generate patch. Copy patches manually into $PATCHES_DIR" >&2
  exit 1
fi
echo "0001-local.patch" > "$PATCHES_DIR/series"
echo "Wrote $PATCHES_DIR/0001-local.patch and series."
