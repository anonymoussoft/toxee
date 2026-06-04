#!/usr/bin/env bash
# Scenarios: S51
# Class: 2proc-l3
# Run the S51 "friend online/offline presence indicator" L3 gate.
#
#   PHASE 1  baseline: boot the paired pair, confirm A sees B online (+roundtrip)
#   PHASE 2  offline:  stop B, A sees B drop offline
#   PHASE 3  back:      relaunch + reboot B, A sees B come back online (+roundtrip)
#
# IMPORTANT: launch_fixture_c_pair.sh / launch_toxee_instance.sh only START the
# process — the restored account is NOT logged in (and the friends list stays
# empty) until a driver boots it via l3_boot_existing_account. So PHASE 1 and
# PHASE 3 use drive_fixture_c_pair.dart (which boots both accounts and confirms
# A<->B online + a message roundtrip); the lightweight presence probe is used
# only for PHASE 2's offline watch against the already-booted A.
#
# A's ws_uri is stable across the whole run (only B is bounced). B is relaunched
# from the SAME app copy + persisted home override launch_fixture_c_pair.sh used.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"
# Mirror launch_fixture_c_pair.sh's app-copy bookkeeping so PHASE 3 reboots B
# from the exact same ToxeeB.app copy it was originally launched from.
COPIES_DIR="$RUNTIME_ROOT/app_copies"
APP_B_COPY="$COPIES_DIR/ToxeeB.app"
B_INSTANCE_JSON="$RUNTIME_ROOT/B/instance.json"

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[presence] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
friend="$(jq -r '.instances.A.friend_tox_id' "$PAIR_MANIFEST")"
if [[ -z "$a_ws" || "$a_ws" == "null" ]]; then
    echo "[presence] ERROR: could not read A ws_uri from $PAIR_JSON" >&2
    exit 1
fi
if [[ -z "$friend" || "$friend" == "null" ]]; then
    echo "[presence] ERROR: could not read friend_tox_id from $PAIR_MANIFEST" >&2
    exit 1
fi
echo "[presence] A ws_uri=$a_ws friend=${friend:0:16}..."

echo "[presence] PHASE 1: boot pair + confirm A<->B online"
dart run tool/mcp_test/drive_fixture_c_pair.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[presence] PHASE 2: take B offline (A sees B go offline)"
"$MCP_DIR/stop_toxee_instance.sh" B
dart run tool/mcp_test/drive_fixture_c_presence.dart "$a_ws" false \
    --timeout-secs 150 --friend-tox "$friend"

echo "[presence] PHASE 3: relaunch + reboot B (A sees B come back online)"
TOXEE_APP_BUNDLE="$APP_B_COPY" "$MCP_DIR/launch_toxee_instance.sh" B
b_ws_new="$(jq -r '.ws_uri' "$B_INSTANCE_JSON")"
if [[ -z "$b_ws_new" || "$b_ws_new" == "null" ]]; then
    echo "[presence] ERROR: could not read new B ws_uri from $B_INSTANCE_JSON" >&2
    exit 1
fi
echo "[presence] new B ws_uri=$b_ws_new"
dart run tool/mcp_test/drive_fixture_c_pair.dart "$a_ws" "$b_ws_new" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[presence] S51 PASS"
