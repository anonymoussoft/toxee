#!/usr/bin/env bash
# Echo peer fixture — Phase 3 foreground helper.
#
# Ad-hoc dev use ONLY. NOT used by any scenario runner. Runs the peer in the
# foreground with stdout/stderr streaming to the TTY, and uses an EXIT trap
# to SIGTERM the peer when the user hits Ctrl+C. The daemon path
# (ensure_echo_peer.sh) cannot use a trap because the script returns while
# the peer continues to run.
#
# Env overrides:
#   ECHO_PEER_BIN              path to peer binary
#   ECHO_PEER_STATE_DIR_BASE   path to state dir parent
#                              (default tool/mcp_test/echo_peer_state)
#   ECHO_PEER_STATE_DIR        full state dir override (skips _BASE if set)
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md "Phase 3 — Daemon + foreground helpers".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PEER_BIN="${ECHO_PEER_BIN:-$MCP_DIR/echo_peer_src/build/echo_peer}"
STATE_DIR_BASE="${ECHO_PEER_STATE_DIR_BASE:-$MCP_DIR/echo_peer_state}"
STATE_DIR="${ECHO_PEER_STATE_DIR:-$STATE_DIR_BASE}"

PEER_PID=""

cleanup() {
    if [[ -n "$PEER_PID" ]] && kill -0 "$PEER_PID" 2>/dev/null; then
        echo
        echo "run_echo_peer_foreground.sh: stopping peer (pid=$PEER_PID) ..." >&2
        kill -TERM "$PEER_PID" 2>/dev/null || true
        # Give it a beat to flush.
        waited=0
        while [[ "$waited" -lt 5 ]] && kill -0 "$PEER_PID" 2>/dev/null; do
            sleep 1
            waited=$((waited + 1))
        done
        if kill -0 "$PEER_PID" 2>/dev/null; then
            kill -KILL "$PEER_PID" 2>/dev/null || true
        fi
    fi
}
trap cleanup EXIT INT TERM

[[ -x "$PEER_BIN" ]] || {
    echo "run_echo_peer_foreground.sh: ERROR: peer binary not found or not executable: $PEER_BIN" >&2
    exit 1
}

mkdir -p "$STATE_DIR"

echo "Foreground mode — Ctrl+C to stop. State dir: $STATE_DIR"

# Launch as a child of THIS shell (no nohup, no setsid) so signals propagate
# and stdout/stderr land on the TTY. We still background and `wait` so the
# EXIT trap can SIGTERM the peer cleanly on Ctrl+C.
ECHO_PEER_STATE_DIR="$STATE_DIR" "$PEER_BIN" &
PEER_PID=$!

# `wait` returns the child's exit status; pass it through.
set +e
wait "$PEER_PID"
rc=$?
set -e

PEER_PID=""  # don't double-kill in cleanup
echo "run_echo_peer_foreground.sh: peer exited with code $rc"
exit "$rc"
