#!/usr/bin/env bash
# Scenarios: S54
# Class: 2proc-l3
# Run the S54 "friend request custom message round-trips to recipient" L3 gate.
#
# FRESH base: launches two blank instances; the driver registers two fresh
# accounts, sets the recipient's autoAcceptFriends=false, sends a friend
# request carrying a distinctive custom message, and asserts the recipient
# observes that exact wording as a pending application (without accepting).
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

echo "[custom-msg] launching FRESH pair (no fixture restore)"
"$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_custom_message.dart "$a_ws" "$b_ws"

echo "[custom-msg] S54 PASS"
