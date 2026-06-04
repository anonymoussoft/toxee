#!/usr/bin/env bash
# Scenarios: S53
# Class: 2proc-l3
# Run the S53 "tap a message notification → opens the conversation" L3 gate
# (ROUTING half only).
#
# The OS banner POST and the OS-level tap remain OS-gated and out of scope. This
# gates the wired in-app routing seam that the OS tap handler feeds:
#   NotificationService.onSelectStream → NotificationMessageListener
#   .onConversationTapped → _routeToNotificationPayload → _openChat →
#   UikitDataFacade.currentConversation.
#
# Restores the paired_for_e2e fixture (A and B already friends with seeded
# history, so a C2C conversation A↔B exists in A's conversation list), boots
# both accounts, then injects a notification tap on A for c2c_<toxB> and asserts
# A's open conversation flips to toxB.
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

echo "[notif-tap] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_notification_tap.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[notif-tap] S53 PASS"
