#!/usr/bin/env bash
# Scenarios: S21, S24
# Class: 2proc-l3
# Run the S21 "send file attachment" + S24 "accept incoming file" L3 gate.
#
# Restores the paired_for_e2e fixture and boots both accounts (the driver boots
# the restored accounts itself), then A sends one small file to B. The receiver
# auto-accepts files under its size limit, so one transfer covers both legs:
# S21 (file message on the sender) and S24 (file accepted + written on B).
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

echo "[file] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_file.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[file] S21/S24 PASS"
