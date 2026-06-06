#!/usr/bin/env bash
# Scenarios: S61, S62
# Class: 2proc-l3
# Fixture C non-media entry point.
#
# This script now has TWO roles (plan section 3.4 made it a thin alias for the
# unified runner, but its original single-gate leaf behavior is preserved so
# the S61/S62 contract is never lost):
#
#   1. THIN ALIAS (default / no positional arg): delegate to
#      fixture_c_unified_runner.dart --tier=non-media, i.e. run ALL non-media
#      Fixture C gates in manifest order. Planning flags such as --dry-run /
#      --list / --plan-json / --validate-only are passed through.
#
#   2. LEAF GATE (legacy modes, unchanged): run only the S61/S62 pair handshake
#      + message-delivery gate via drive_fixture_c_pair.dart.
#      Modes:
#        fresh           register A/B, create friendship, then A->B/B->A text
#        paired_for_e2e  restore the paired fixture, boot existing accounts, then text
#      The fresh mode covers the state-level S61 handshake contract plus S62
#      message delivery. The paired_for_e2e mode is the fast reusable S62 base
#      for follow-on two-process scenarios. (run_fixture_c_suite.sh NOTE-skips
#      this script as the alias/self to avoid recursion, so the S61/S62 leaf is
#      only reachable via these explicit modes.)
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNNER_REL="tool/mcp_test/fixture_c_unified_runner.dart"
RUNNER_PATH="$REPO_ROOT/$RUNNER_REL"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"

usage() {
    cat <<EOF
usage: run_fixture_c_non_media.sh [runner flags] | [fresh|paired_for_e2e]

Two roles:
  (flags only / no mode)  THIN ALIAS -> $RUNNER_REL --tier=non-media
                          (runs ALL non-media Fixture C gates in manifest order)
  --dry-run               alias mode, print the planned commands only
  --list                  alias mode, list resolved non-media entries
  --plan-json             alias mode, emit grouped plan JSON
  --validate-only         alias mode, validate planning inputs without running
  --include-destructive   alias mode, also run destructive gates (kick)
  fresh                   LEAF: fresh A/B registration, request/accept, ping/pong
  paired_for_e2e          LEAF: restore paired_for_e2e A/B, boot existing, ping/pong

Environment (LEAF modes):
  TOXEE_MULTI_LAUNCH_METHOD=direct   recommended default
  TOXEE_APP_BUNDLE=/path/Toxee.app   optional debug app override
EOF
}

leaf_mode=""
for arg in "$@"; do
    case "$arg" in
        -h|--help|help)
            usage
            exit 0
            ;;
        fresh|paired_for_e2e|paired|restored)
            leaf_mode="$arg"
            break
            ;;
        --*)
            ;;
        *)
            echo "run_fixture_c_non_media.sh: unknown mode: $arg" >&2
            usage >&2
            exit 64
            ;;
    esac
done

# --- Role dispatch -----------------------------------------------------------
# No leaf mode => thin alias for the unified runner, pinned to non-media only.
if [[ -z "$leaf_mode" ]]; then
    runner_args=()
    have_tier=0
    for a in "$@"; do
        if [[ "$a" == --tier=* && "$a" != --tier=non-media ]]; then
            echo "run_fixture_c_non_media.sh: refusing '$a' — this alias only runs --tier=non-media." >&2
            echo "Use tool/mcp_test/run_fixture_c_suite.sh --tier=<media|all> directly." >&2
            exit 64
        fi
        [[ "$a" == --tier=* ]] && have_tier=1
        runner_args+=("$a")
    done
    if [[ ! -f "$RUNNER_PATH" ]]; then
        echo "run_fixture_c_non_media.sh: unified runner not found: $RUNNER_PATH" >&2
        exit 70
    fi
    [[ "$have_tier" -eq 1 ]] || runner_args=(--tier=non-media ${runner_args[@]:+"${runner_args[@]}"})
    cd "$REPO_ROOT"
    exec dart run "$RUNNER_REL" ${runner_args[@]:+"${runner_args[@]}"}
fi

# --- Legacy LEAF behavior (S61/S62 pair gate) --------------------------------
mode="$leaf_mode"
case "$mode" in
    paired|restored)
        mode="paired_for_e2e"
        ;;
    fresh|paired_for_e2e)
        ;;
    *)
        echo "run_fixture_c_non_media.sh: unknown mode: $mode" >&2
        usage >&2
        exit 64
        ;;
esac

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

if [[ "${TOXEE_MULTI_LAUNCH_METHOD:-direct}" == "open" ]]; then
    echo "WARN: TOXEE_MULTI_LAUNCH_METHOD=open is experimental for Fixture C; direct is the stable ping/pong path." >&2
fi

echo "[fixture-c] non-media mode=$mode"
if [[ "$mode" == "paired_for_e2e" ]]; then
    TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"
else
    "$MCP_DIR/launch_fixture_c_pair.sh"
fi

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

driver_args=("$a_ws" "$b_ws")
if [[ "$mode" == "paired_for_e2e" ]]; then
    driver_args+=(--fixture-manifest "$PAIR_MANIFEST")
fi

dart run tool/mcp_test/drive_fixture_c_pair.dart "${driver_args[@]}"
echo "[fixture-c] non-media mode=$mode PASS"
