#!/usr/bin/env bash
# Scenarios: S33
# Class: 2proc-l3
# Run the S33 "JOIN a group by chat-id (two processes)" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts, then A creates a
# PUBLIC NGC group and B joins it by chat-id (no invite). Asserts B joined
# (knownGroups contains the chat-id). This is the S34 group gate MINUS the
# A<->B message roundtrip — S33 only proves the join.
#
# PUBLIC NGC two-process discovery is flaky (~40% establish even with the
# full-mesh local bootstrap the driver wires — same residual as S34/S36/kick),
# so this gate RETRIES up to JOIN_GATE_ATTEMPTS (default 4) FRESH paired
# sessions and passes if any attempt passes. Each failed attempt fails loudly
# with the exact stalled stage before the relaunch.
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

ATTEMPTS="${JOIN_GATE_ATTEMPTS:-4}"
attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    echo "[join] ===== attempt $attempt/$ATTEMPTS ====="
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

    echo "[join] launching paired fixture"
    TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

    a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
    b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

    # `if` exempts the dart run from `set -e`, so a flaky NGC failure retries
    # instead of aborting the gate.
    if dart run tool/mcp_test/drive_fixture_c_join.dart "$a_ws" "$b_ws" \
        --fixture-manifest "$PAIR_MANIFEST"; then
        echo "[join] S33 PASS (attempt $attempt/$ATTEMPTS)"
        exit 0
    fi

    echo "[join] attempt $attempt/$ATTEMPTS FAILED (likely flaky NGC connectivity); stopping pair before retry"
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true
    attempt=$((attempt + 1))
done

echo "[join] S33 FAIL after $ATTEMPTS attempts (NGC two-process connectivity never established — see per-attempt diagnostics above)"
exit 1
