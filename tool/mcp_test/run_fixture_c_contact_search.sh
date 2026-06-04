#!/usr/bin/env bash
# Scenarios: S49
# Class: 2proc-l3
# Run the S49 "contact-list search filter" L3 gate (B-block: in-page contact
# search filter).
#
# Restores the paired_for_e2e fixture (A and B already friends, A has exactly
# one friend 'echo_live_test'), boots both accounts, then drives instance A's
# in-page contact-search FILTER via l3_contact_search and asserts:
#   A1 — a matching query ('echo') returns matches (>=1, <= full count)
#   A2 — a non-matching nonce query filters everything out (0)
#
# B is launched only as the paired partner so A's friend list hydrates from the
# restored fixture; the contact list is local to A, so no live friend-online
# state is required. This gates the in-page contact search FILTER
# deterministically; the search field itself renders in the contact AppBar with
# ValueKey('contact_search_field') (the fix that un-stubbed the Container()).
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

echo "[contact-search] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_contact_search.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[contact-search] S49 PASS"
