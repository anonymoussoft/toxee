#!/usr/bin/env bash
# Scenarios: S79
# Class: 2proc-l3
# Run the S79 "set self avatar via native picker" L3 gate.
#
# The native macOS NSOpenPanel cannot be driven headlessly, so the L3 override
# (l3_pick_avatar) bypasses it and exercises the REAL pickAndPersistAvatar
# copy+persist flow: a sandbox-safe temp source is written from the supplied
# content, copied into the per-account avatars dir, and the resulting path is
# persisted as the self avatar. The driver asserts on instance A only.
#
# Restores the paired_for_e2e fixture (A and B booted), then has A pick+persist
# a new avatar and asserts the returned destPath is a plausible per-account
# avatar path. Friend propagation of the avatar (kind-1 file transfer) is the
# SEPARATE S52 gate and is NOT exercised here. The launch restore wipes any
# per-run profile/avatar change, so dirtying the fixture is safe.
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

echo "[avatar-picker] launching paired fixture"
TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

dart run tool/mcp_test/drive_fixture_c_avatar_picker.dart "$a_ws" "$b_ws" \
    --fixture-manifest "$PAIR_MANIFEST"

echo "[avatar-picker] S79 PASS"
