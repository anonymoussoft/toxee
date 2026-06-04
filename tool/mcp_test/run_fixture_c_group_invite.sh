#!/usr/bin/env bash
# Scenarios: S47, S81
# Class: 2proc-l3
# Run the S47 "auto-accept group invite toggle" + S81 "invite a friend to a
# group" L3 gate (one two-process test).
#
# Restores the paired_for_e2e fixture, boots both accounts, then: B turns
# autoAcceptGroupInvites ON, A creates a group and INVITES the friend B to it
# (S81 invite-send), and B auto-joins the group with no manual join (S47
# auto-accept).
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

echo "[group-invite] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_group_invite.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[group-invite] S47/S81 PASS"
