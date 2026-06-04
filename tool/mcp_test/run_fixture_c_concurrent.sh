#!/usr/bin/env bash
# Scenarios: S64
# Class: 2proc-l3
# Run the S64 "concurrent send (two processes)" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts, then interleaves
# N sends each way and asserts both conversations converge with no loss, no
# duplicate msgIDs, and per-stream timestamp ordering preserved.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PAIR_JSON="$MCP_DIR/.multi_instance_runtime/pair.json"
PAIR_MANIFEST="$MCP_DIR/fixtures/paired_for_e2e_manifest.json"
N="${1:-10}"

cleanup() {
    "$MCP_DIR/stop_fixture_c_pair.sh" || true
}
trap cleanup EXIT INT TERM

cd "$REPO_ROOT"
"$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

echo "[concurrent] launching paired fixture (N=$N each way)"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_concurrent.dart "$a_ws" "$b_ws" \
    --n "$N" --fixture-manifest "$PAIR_MANIFEST"

echo "[concurrent] S64 PASS"
