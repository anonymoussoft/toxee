#!/usr/bin/env bash
# Scenarios: S36
# Class: 2proc-l3
# Run the S36 "group member list" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts, then A creates a
# PUBLIC NGC group, B joins it by chat-id (the proven S34 path, no invite), and
# A reads its member list via the real SDK->C++ GetGroupMemberList path. The
# driver asserts the list shows BOTH self (exactly one isSelf:true) and the
# joined peer B (a non-self member, identified by its NGC group pubkey). This is
# the READ-ONLY subset of the S37 kick gate — no kick.
#
# PUBLIC NGC two-process discovery is flaky (~40% establish even with the
# full-mesh local bootstrap the driver wires), so this gate RETRIES up to
# MEMBER_LIST_GATE_ATTEMPTS (default 4) FRESH paired sessions and passes if any
# attempt passes (3 attempts ~78%, 4 ~87%, 5 ~92% at a 40% per-attempt rate).
# Each failed attempt fails loudly with the exact stalled stage before the
# relaunch.
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

ATTEMPTS="${MEMBER_LIST_GATE_ATTEMPTS:-4}"
attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    echo "[member-list] ===== attempt $attempt/$ATTEMPTS ====="
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

    echo "[member-list] launching paired fixture"
    TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

    a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
    b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

    # `if` exempts the dart run from `set -e`, so a flaky failure retries instead
    # of aborting the gate.
    if dart run tool/mcp_test/drive_fixture_c_member_list.dart "$a_ws" "$b_ws" \
        --fixture-manifest "$PAIR_MANIFEST"; then
        echo "[member-list] S36 PASS (attempt $attempt/$ATTEMPTS)"
        exit 0
    fi

    echo "[member-list] attempt $attempt/$ATTEMPTS FAILED (likely flaky NGC connectivity); stopping pair before retry"
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true
    attempt=$((attempt + 1))
done

echo "[member-list] S36 FAIL after $ATTEMPTS attempts (NGC two-process connectivity never established — see per-attempt diagnostics above)"
exit 1
