#!/usr/bin/env bash
# Scenarios: S88
# Class: 2proc-l3
# Run the S88 "send an image message" L3 gate.
#
# Reuses the S21/S24 file harness with --image: A sends a small .png to B over
# the paired_for_e2e fixture, and the receiver must classify it as
# mediaKind=="image" (the image-message plumbing, D3 / FakeMsgProvider.sendImage
# → file send with an image extension). Same paired base + driver as
# run_fixture_c_file.sh; only the file extension + the receiver mediaKind
# assertion differ, so this cannot regress S21/S24.
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

echo "[image] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_file.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST" \
    --image

echo "[image] S88 PASS (receiver mediaKind=image)"
