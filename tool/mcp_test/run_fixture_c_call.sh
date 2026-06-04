#!/usr/bin/env bash
# Scenarios: S65, S66, S67, S68, S74, S75, S76
# Class: 2proc-l3
# Run the Fixture C media/call L3 gate on the paired_for_e2e base.
#
# Modes:
#   reject   S68: A calls, B rings, B rejects, both return to ended/idle
#   voice    S65/S67/S74/S76: A voice-calls, B accepts, both inCall, A mutes, A hangs up
#   video    S66/S75: A video-calls, B accepts, both inCall, A toggles video, A hangs up
#
# Booting the restored accounts is done by drive_fixture_c_pair.dart
# (l3_boot_existing_account) — launch_*.sh only starts the process; the account
# is not logged in (and ToxAV/calling is not reachable) until the driver boots
# it and both sides are online. Then drive_fixture_c_call.dart drives the call.
#
# OS note: macOS microphone/camera (TCC) authorization for com.toxee.app must be
# granted ahead of time — a first-time TCC prompt would block this headless run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"

mode="${1:-voice}"
case "$mode" in
    reject) call_flags=(--reject) ;;
    voice)  call_flags=() ;;
    video)  call_flags=(--video --toggle-video) ;;
    -h|--help|help)
        echo "usage: run_fixture_c_call.sh [reject|voice|video]"; exit 0 ;;
    *)
        echo "run_fixture_c_call.sh: unknown mode: $mode" >&2
        echo "usage: run_fixture_c_call.sh [reject|voice|video]" >&2
        exit 64 ;;
esac

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[call] launching paired fixture (mode=$mode)"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

echo "[call] booting pair + confirming A<->B online"
dart run tool/mcp_test/drive_fixture_c_pair.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[call] driving call (mode=$mode)"
dart run tool/mcp_test/drive_fixture_c_call.dart "$a_ws" "$b_ws" \
    "${call_flags[@]+"${call_flags[@]}"}"

echo "[call] S6x ($mode) PASS"
