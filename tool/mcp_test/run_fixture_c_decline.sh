#!/usr/bin/env bash
# Scenarios: S27
# Class: 2proc-l3
# Run the S27 "decline a friend request leaves no friendship" L3 gate.
#
# FRESH base: launches two blank instances; the driver registers two fresh
# accounts, has B send a friend request to A, waits for the pending application
# to reach A, has A decline it, and asserts the application is gone from A's
# friendApplications[] with no friendship created (B not in A's friends[]).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[decline] launching FRESH pair (no fixture restore)"
"$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_decline.dart "$a_ws" "$b_ws"

echo "[decline] S27 PASS"
