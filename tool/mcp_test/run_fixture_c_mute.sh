#!/usr/bin/env bash
# Scenarios: S83
# Class: 2proc-l3
# Run the S83 "mute a conversation -> inbound notification suppressed" L3 gate
# (mute-STATE half).
#
# The OS-banner-absence proof (a log stream on UNUserNotificationCenter) is
# OS-gated and OUT OF SCOPE. This gate restores the paired_for_e2e fixture
# (A and B already friends with seeded history, so A's conversation list has a
# c2c conversation for B), mutes that conversation via l3_set_c2c_recv_opt, and
# asserts the UIKit conversation-cache recvOpt that _shouldSuppress reads is set
# to 2 (recvOpt != 0 is exactly what _shouldSuppress suppresses on).
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

echo "[mute] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_mute.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[mute] S83 PASS"
