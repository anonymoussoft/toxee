#!/usr/bin/env bash
# Scenarios: S69
# Class: 2proc-l3
# Run the S69 "call network drop (two processes)" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts, establishes a real
# call between A and B, then triggers A's reconnect path via the
# l3_call_action `network_drop` action (CallServiceManager.markReconnecting()).
# Asserts the call is established (A1), A enters the reconnecting state (A2,
# lenient — the transient can be missed by 1s polling), and that after the 8s
# grace timer expires the call ends (A3 = ended after grace, the hard gate).
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

echo "[network-drop] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_network_drop.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[network-drop] S69 PASS"
