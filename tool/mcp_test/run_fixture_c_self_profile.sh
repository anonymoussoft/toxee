#!/usr/bin/env bash
# Scenarios: S52
# Class: 2proc-l3
# Run the S52 "self profile change propagates to a friend" L3 gate.
#
# Restores the paired_for_e2e fixture (A and B already friends), boots both
# accounts, then has A change its OWN Tox nickname via l3_set_self_profile and
# asserts the paired friend B observes the new nickname on its friend-list
# entry for A over the live DHT connection (friend_name callback).
#
# NOTE: avatar propagation (kind-1 file transfer) is a documented FOLLOW-UP and
# is NOT gated here — only the nickname leg is exercised. The launch restore
# wipes any per-run profile change, so dirtying the fixture is safe.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[self-profile] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_self_profile.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[self-profile] S52 PASS"
