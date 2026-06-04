#!/usr/bin/env bash
# Scenarios: S63
# Class: 2proc-l3
# Run the S63 "typing indicator propagates to a friend" L3 gate (TYPING leg).
#
# Restores the paired_for_e2e fixture (A and B already friends), boots both
# accounts, then has A send a Tox typing notification toward B via l3_set_typing
# and asserts the paired friend B observes isTyping==true on its friend-list
# entry for A over the live DHT connection (typing callback). A re-sends
# typing=true periodically because the indicator expires ~3s after the last
# event; turning typing off is asserted by B's indicator dropping back to false.
#
# NOTE: the read-receipt half of S63 is a documented no-op and is OUT OF SCOPE
# here — only the typing leg is gated. The launch restore wipes any per-run
# typing state, so dirtying the fixture is safe.
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

echo "[typing] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_typing.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[typing] S63-typing PASS"
