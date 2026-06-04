#!/usr/bin/env bash
# Scenarios: S37
# Class: 2proc-l3
# Run the S37 "group moderation — KICK leg" L3 gate.
#
# Restores the paired_for_e2e fixture, boots both accounts; A creates a group, B
# joins/is-invited, A kicks B via the real SDK->C++ tox_group_kick_peer path. The
# driver verifies B's knownGroups grows on join and drops on kick.
#
# DEFAULT = PRIVATE group + friend-link INVITE. Peers connect over the existing
# friend link (no public-DHT discovery), so it is reliable + fast: measured 8/8
# (resolves in ~6s) and spec-complete — it asserts B-SIDE removal (B's knownGroups
# drops the group), exercising BOTH native fixes: the invite auto-join now
# propagates to B's knownGroups (DartNotifyGroupJoin) and the kick drops it
# (self-kick -> DartNotifyGroupQuit).
#
# KICK_GATE_PUBLIC=1 → the legacy PUBLIC group + chat-id-join path instead.
# PUBLIC two-process DHT discovery is flaky (~40% establish even with the
# full-mesh local bootstrap), so the gate RETRIES up to KICK_GATE_ATTEMPTS FRESH
# paired sessions and passes if any attempt passes. PRIVATE rarely needs a retry,
# so KICK_GATE_ATTEMPTS defaults to 2 (raise it for the flakier PUBLIC path).
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

# DEFAULT to the PRIVATE group + friend-link-invite path (reliable + spec-complete
# B-side). KICK_GATE_PUBLIC=1 forces the legacy PUBLIC group + chat-id-join path.
PRIVATE_FLAG="--private"
[[ "${KICK_GATE_PUBLIC:-}" == "1" ]] && PRIVATE_FLAG=""

ATTEMPTS="${KICK_GATE_ATTEMPTS:-2}"
attempt=1
while [ "$attempt" -le "$ATTEMPTS" ]; do
    echo "[kick] ===== attempt $attempt/$ATTEMPTS ====="
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true

    echo "[kick] launching paired fixture"
    TOXEE_FIXTURE_C_RESTORE=paired_for_e2e "$MCP_DIR/launch_fixture_c_pair.sh"

    a_ws="$(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
    b_ws="$(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"

    # `if` exempts the dart run from `set -e`, so a flaky failure retries instead
    # of aborting the gate.
    if dart run tool/mcp_test/drive_fixture_c_kick.dart "$a_ws" "$b_ws" \
        --fixture-manifest "$PAIR_MANIFEST" $PRIVATE_FLAG; then
        echo "[kick] S37 PASS (attempt $attempt/$ATTEMPTS)"
        exit 0
    fi

    echo "[kick] attempt $attempt/$ATTEMPTS FAILED (likely flaky NGC connectivity); stopping pair before retry"
    "$MCP_DIR/stop_fixture_c_pair.sh" >/dev/null 2>&1 || true
    attempt=$((attempt + 1))
done

echo "[kick] S37 FAIL after $ATTEMPTS attempts (NGC two-process connectivity never established — see per-attempt diagnostics above)"
exit 1
