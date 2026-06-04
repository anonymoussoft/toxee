#!/usr/bin/env bash
# Scenarios: S61, S62
# Class: 2proc-l3
# Fixture C non-media entry point.
#
# This script now has TWO roles (plan section 3.4 made it a thin alias for the
# tiered suite runner, but its original single-gate leaf behavior is preserved
# so the S61/S62 contract is never lost):
#
#   1. THIN ALIAS (default / no positional arg): delegate to
#      run_fixture_c_suite.sh --tier=non-media, i.e. run ALL non-media Fixture C
#      gates in manifest order. --include-destructive is passed through.
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
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"

usage() {
    cat <<EOF
usage: run_fixture_c_non_media.sh [fresh|paired_for_e2e] [--include-destructive]

Two roles:
  (no arg)                THIN ALIAS -> run_fixture_c_suite.sh --tier=non-media
                          (runs ALL non-media Fixture C gates in manifest order)
  --include-destructive   alias mode, also run destructive gates (kick)
  fresh                   LEAF: fresh A/B registration, request/accept, ping/pong
  paired_for_e2e          LEAF: restore paired_for_e2e A/B, boot existing, ping/pong

Environment (LEAF modes):
  TOXEE_MULTI_LAUNCH_METHOD=direct   recommended default
  TOXEE_APP_BUNDLE=/path/Toxee.app   optional debug app override
EOF
}

# --- Role dispatch -----------------------------------------------------------
# No positional mode (or only flags) => thin alias for the tiered suite runner.
arg1="${1:-}"
case "$arg1" in
    ""|--tier=*|--include-destructive)
        # Forward args; force --tier=non-media if none was given. A script named
        # "non_media" must not silently run other tiers (codex final review P3):
        # reject any explicit tier that isn't non-media — use
        # run_fixture_c_suite.sh directly for media/all.
        # `${arr[@]:+...}` guards empty-array-under-set-u (bash 3.2 footgun) — the
        # common no-arg invocation makes suite_args empty before the default tier
        # is prepended.
        suite_args=()
        have_tier=0
        for a in "$@"; do
            if [[ "$a" == --tier=* && "$a" != --tier=non-media ]]; then
                echo "run_fixture_c_non_media.sh: refusing '$a' — this alias only runs --tier=non-media." >&2
                echo "Use tool/mcp_test/run_fixture_c_suite.sh --tier=<media|all> directly." >&2
                exit 64
            fi
            [[ "$a" == --tier=* ]] && have_tier=1
            suite_args+=("$a")
        done
        [[ "$have_tier" -eq 1 ]] || suite_args=(--tier=non-media ${suite_args[@]:+"${suite_args[@]}"})
        exec "$MCP_DIR/run_fixture_c_suite.sh" ${suite_args[@]:+"${suite_args[@]}"}
        ;;
    -h|--help|help)
        usage
        exit 0
        ;;
esac

# --- Legacy LEAF behavior (S61/S62 pair gate) --------------------------------
mode="$arg1"
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
