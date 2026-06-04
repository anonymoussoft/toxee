#!/usr/bin/env bash
# Product-screenshot pipeline — one-command entry point.
#
#   ./tool/screenshots/capture.sh [--reset] [--build] [--p0-only]
#                                 [--include-incall] [--sync-site]
#
# Launches 4 isolated toxee instances (ShotA hero + ShotB/C/D partners) from
# a PERSISTENT self-contained seed root, seeds rich demo data once (reused
# on later runs via auto-login), drives the real UI, and writes the scene
# screenshots to ./screenshot/.
#
#   --reset           surgical seed rebuild: wipe the seed root + container
#                     leftovers + ONLY the toxee_shot*. prefixed defaults keys
#                     (never `defaults delete com.toxee.app` — plan F1)
#   --build           (re)build the debug app WITH the L3 surface via
#                     MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh
#   --p0-only         capture only the P0 scenes
#   --include-incall  also capture the in-call scene (accept starts mic
#                     capture → macOS may prompt; off by default)
#   --sync-site       downscale curated shots into doc/product/assets/
#
# While the capture runs the script owns window focus — don't type or click.
#
# Plan: docs/plans/2026-06-03-product-screenshots-and-landing-page.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
SEED_ROOT="$REPO_ROOT/tool/screenshots/_seed_runtime"
OUT_DIR="$REPO_ROOT/screenshot"
SITE_ASSETS="$REPO_ROOT/doc/product/assets"
APP_BUNDLE="$REPO_ROOT/build/macos/Build/Products/Debug/Toxee.app"
CONTAINER_MULTI_ROOT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/multi_instance"
INSTANCES=(ShotA ShotB ShotC ShotD)

RESET=0 BUILD=0 SYNC_SITE=0
DART_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --reset) RESET=1 ;;
        --build) BUILD=1 ;;
        --sync-site) SYNC_SITE=1 ;;
        --p0-only|--include-incall) DART_ARGS+=("$arg") ;;
        *) echo "unknown flag: $arg" >&2; exit 64 ;;
    esac
done

# shellcheck source=../mcp_test/_multi_instance_lib.sh
. "$MCP_DIR/_multi_instance_lib.sh"

# ── --reset: surgical seed rebuild ──────────────────────────────────────────
if [[ "$RESET" == "1" ]]; then
    echo "==> reset: wiping seed root $SEED_ROOT"
    rm -rf "$SEED_ROOT"
    for inst in "${INSTANCES[@]}"; do
        rm -rf "$CONTAINER_MULTI_ROOT/$inst"
    done
    echo "==> reset: deleting toxee_shot*. prefixed defaults keys (surgical)"
    /usr/bin/python3 - <<'PY'
import plistlib, subprocess
proc = subprocess.run(
    ["defaults", "export", "com.toxee.app", "-"],
    capture_output=True,
)
if proc.returncode != 0 or not proc.stdout.strip():
    print("    (no com.toxee.app defaults domain — nothing to clean)")
    raise SystemExit(0)
keys = [
    k for k in plistlib.loads(proc.stdout)
    if k.startswith(("toxee_shota.", "toxee_shotb.", "toxee_shotc.", "toxee_shotd."))
]
for k in keys:
    subprocess.run(["defaults", "delete", "com.toxee.app", k], capture_output=True)
print(f"    removed {len(keys)} prefixed keys")
PY
fi

# ── build (opt-in, or forced when the bundle is missing) ────────────────────
if [[ "$BUILD" == "1" || ! -x "$APP_BUNDLE/Contents/MacOS/Toxee" ]]; then
    echo "==> building debug app with the L3 surface (MCP_BINDING=skill)"
    (cd "$REPO_ROOT" && MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh)
fi

# ── refresh per-instance .app copies (mtime vs source — stale-dylib gotcha) ─
COPIES_DIR="$SEED_ROOT/app_copies"
mkdir -p "$COPIES_DIR"
SRC_EXE="$APP_BUNDLE/Contents/MacOS/Toxee"
for inst in ShotB ShotC ShotD; do
    COPY="$COPIES_DIR/Toxee$inst.app"
    COPY_EXE="$COPY/Contents/MacOS/Toxee"
    if [[ ! -x "$COPY_EXE" || "$SRC_EXE" -nt "$COPY_EXE" ]]; then
        echo "==> refreshing app copy for $inst"
        rm -rf "$COPY"
        cp -R "$APP_BUNDLE" "$COPY"
    fi
done

# ── launch instances (persistent, self-contained seed root) ─────────────────
PIDS=()
cleanup() {
    for inst in "${INSTANCES[@]}"; do
        local_json="$SEED_ROOT/$inst/instance.json"
        [[ -f "$local_json" ]] || continue
        pid="$(jq -r '.pid // empty' "$local_json" 2>/dev/null || true)"
        [[ -n "$pid" ]] && _mi_stop_with_grace "$pid" 5 || true
    done
}
trap cleanup EXIT

for inst in "${INSTANCES[@]}"; do
    echo "==> launching $inst"
    bundle="$APP_BUNDLE"
    [[ "$inst" != "ShotA" ]] && bundle="$COPIES_DIR/Toxee$inst.app"
    # App-support stays at the launcher DEFAULT (inside the macOS app
    # container: .../com.toxee.app/multi_instance/<inst>) — the sandboxed app
    # cannot write to repo paths, so a seed-root app-support override fails
    # with EPERM at registration. Account data persistence still holds; the
    # container Shot* dirs are covered by --reset.
    TOXEE_MULTI_RUNTIME_ROOT="$SEED_ROOT" \
        TOXEE_APP_BUNDLE="$bundle" \
        "$MCP_DIR/launch_toxee_instance.sh" "$inst"
done

# ── drive: seed phase → restart hero → scene phase ──────────────────────────
# Seeding leaves NON-persisted live-session artifacts in the hero's
# conversation list (sender-side raw-key ghost rows, live-path "[Custom]"
# bubbles); restarting ShotA between phases makes the scene walk render the
# persisted truth a real user sees on launch.
mkdir -p "$OUT_DIR"
set +e
# ${arr[@]+...} guard: macOS ships bash 3.2, where "${arr[@]}" on an empty
# array trips `set -u`.
(cd "$REPO_ROOT" && dart run tool/screenshots/capture_product_screenshots.dart \
    --seed-root "$SEED_ROOT" --out "$OUT_DIR" --seed-only)
DART_EXIT=$?
if [[ "$DART_EXIT" == "0" ]]; then
    # Restart the hero AND the call peer: ShotA so the scene walk renders
    # persisted truth (no live-session ghost rows / [Custom] bubbles), ShotB
    # because a previous run's completed call leaves its TUICallKitAdapter
    # refusing new calls ("adapter returned false") until a fresh boot.
    for inst in ShotA ShotB; do
        echo "==> restarting $inst before the scene walk"
        pid="$(jq -r '.pid // empty' "$SEED_ROOT/$inst/instance.json" 2>/dev/null || true)"
        [[ -n "$pid" ]] && _mi_stop_with_grace "$pid" 5 || true
        bundle="$APP_BUNDLE"
        [[ "$inst" != "ShotA" ]] && bundle="$COPIES_DIR/Toxee$inst.app"
        TOXEE_MULTI_RUNTIME_ROOT="$SEED_ROOT" \
            TOXEE_APP_BUNDLE="$bundle" \
            "$MCP_DIR/launch_toxee_instance.sh" "$inst"
    done
    (cd "$REPO_ROOT" && dart run tool/screenshots/capture_product_screenshots.dart \
        --seed-root "$SEED_ROOT" --out "$OUT_DIR" --scenes-only \
        ${DART_ARGS[@]+"${DART_ARGS[@]}"})
    DART_EXIT=$?
fi
set -e
if [[ "$DART_EXIT" == "2" ]]; then
    echo "" >&2
    echo "Seed state drifted (see doctor output above). Re-run with --reset." >&2
fi
if [[ "$DART_EXIT" != "0" ]]; then
    echo "" >&2
    echo "Hint: 'extension never registered' means the .app lacks the L3" >&2
    echo "surface — rebuild with: ./tool/screenshots/capture.sh --build" >&2
    exit "$DART_EXIT"
fi

# ── --sync-site: curated downscaled copies for the product page ─────────────
if [[ "$SYNC_SITE" == "1" ]]; then
    echo "==> syncing curated shots to $SITE_ASSETS"
    mkdir -p "$SITE_ASSETS"
    for png in "$OUT_DIR"/*.png; do
        [[ -f "$png" ]] || continue
        out="$SITE_ASSETS/$(basename "$png")"
        sips --resampleWidth 1280 "$png" --out "$out" >/dev/null
    done
    echo "    $(ls "$SITE_ASSETS" | wc -l | tr -d ' ') assets in doc/product/assets/"
fi

echo ""
echo "✅ screenshots in $OUT_DIR (seed root preserved for reuse: $SEED_ROOT)"
