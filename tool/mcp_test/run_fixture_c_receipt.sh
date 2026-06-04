#!/usr/bin/env bash
# Scenarios: S63
# Class: 2proc-l3
# Run the S63 "read-receipts" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts, then has A send a
# nonce message to B and asserts A's sent message flips isReceived=true after B
# auto-sends a 'received' delivery receipt that A processes (the receipt
# round-trip). This validates the read-receipt mechanism end-to-end; the 'read'
# variant (isRead) fires on explicit markMessageAsRead (conversation open) and
# is not asserted here.
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

echo "[receipt] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_receipt.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[receipt] S63 PASS"
