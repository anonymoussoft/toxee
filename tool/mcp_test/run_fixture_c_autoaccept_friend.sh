#!/usr/bin/env bash
# Scenarios: S46
# Class: 2proc-l3
# Run the S46 "autoAcceptFriends=true auto-accepts inbound friend request" L3 gate.
#
# FRESH base: launches two blank instances; the driver registers two fresh
# accounts, sets the recipient's autoAcceptFriends=true, sends a friend request,
# and asserts the recipient auto-accepts it into the friend list (no manual
# accept) with no lingering pending application.
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

echo "[autoaccept-friend] launching FRESH pair (no fixture restore)"
"$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_autoaccept_friend.dart "$a_ws" "$b_ws"

echo "[autoaccept-friend] S46 PASS"
