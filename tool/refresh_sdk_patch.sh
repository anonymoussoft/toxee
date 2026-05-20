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
if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "SDK dir is not a git repo; cannot generate patch. Copy patches manually into $PATCHES_DIR" >&2
  exit 1
fi

SERIES_FILE="$PATCHES_DIR/series"
if [ ! -f "$SERIES_FILE" ]; then
  echo "No existing series file at $PATCHES_DIR/series. Add at least one patch filename to series before refresh." >&2
  exit 1
fi

# Read existing series, filtering blanks and comment lines.
SERIES_ENTRIES=()
while IFS= read -r line || [ -n "$line" ]; do
  trimmed="$(echo "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  if [ -z "$trimmed" ]; then
    continue
  fi
  case "$trimmed" in
    \#*) continue ;;
  esac
  SERIES_ENTRIES+=("$trimmed")
done < "$SERIES_FILE"

if [ "${#SERIES_ENTRIES[@]}" -eq 0 ]; then
  echo "No existing series file at $PATCHES_DIR/series. Add at least one patch filename to series before refresh." >&2
  exit 1
fi

if [ "${#SERIES_ENTRIES[@]}" -gt 1 ]; then
  {
    echo "refresh_sdk_patch.sh: multi-patch series detected (${#SERIES_ENTRIES[@]} entries); refusing to overwrite."
    echo ""
    echo "Regenerate manually:"
    echo "  cd $SDK_DIR"
    echo "  # 1) commit each logical change on top of the 'baseline' ref"
    echo "  git format-patch baseline..HEAD -o \"$PATCHES_DIR\""
    echo "  # 2) update the series file to list each generated patch in apply order:"
    echo "  ls \"$PATCHES_DIR\"/*.patch | xargs -n1 basename > \"$PATCHES_DIR/series\""
    echo "  # 3) re-bootstrap so vendor_state.patches_sha256 is refreshed:"
    echo "  (cd \"$ROOT\" && dart run tool/bootstrap_deps.dart --force)"
  } >&2
  exit 1
fi

PATCH_NAME="${SERIES_ENTRIES[0]}"
# Prefer the 'baseline' ref planted by apply_sdk_patches.dart; fall back to HEAD.
if git rev-parse --verify baseline >/dev/null 2>&1; then
  DIFF_BASE="baseline"
else
  DIFF_BASE="HEAD"
fi
git diff "$DIFF_BASE" -- . > "$PATCHES_DIR/$PATCH_NAME" || true
if [ ! -s "$PATCHES_DIR/$PATCH_NAME" ]; then
  rm -f "$PATCHES_DIR/$PATCH_NAME"
  echo "No local changes in SDK dir; no patch written."
  exit 0
fi
echo "Wrote $PATCHES_DIR/$PATCH_NAME (diff base: $DIFF_BASE)."
