#!/usr/bin/env bash
# Echo peer fixture — Phase 3 daemon stop.
#
# Reads tool/mcp_test/echo_peer.json, validates the pid+start_time+cmdline
# triple still describes the live process, then SIGTERMs (with SIGKILL
# fallback after a grace period). If validation fails — meaning the recorded
# process is gone and its pid may have been recycled — we clear the stale
# json WITHOUT signaling anyone, since signaling a recycled pid is dangerous.
#
# Concurrent with ensure_echo_peer.sh via the same mkdir lock. We ALWAYS
# acquire the lock BEFORE deciding "nothing to stop", so a `stop` racing a
# cold `ensure` cannot return success while the peer is mid-launch (codex
# Round 13 Z4).
#
# Env override:
#   ECHO_PEER_STOP_WAIT_SECS  (default 5) SIGTERM → SIGKILL grace
#   ECHO_PEER_LOCK_WAIT_SECS  (default 30) seconds to wait for the lock dir
#   ECHO_PEER_VERBOSE         (default unset) any non-empty value enables
#                             diagnostic stdout on no-op paths
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md "Phase 3 — Daemon + foreground helpers".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
JSON_FILE="$MCP_DIR/echo_peer.json"
LOCK_DIR="$MCP_DIR/.echo_peer.lock"
PEER_BIN_DEFAULT="$MCP_DIR/echo_peer_src/build/echo_peer"
PEER_BIN="${ECHO_PEER_BIN:-$PEER_BIN_DEFAULT}"

STOP_WAIT_SECS="${ECHO_PEER_STOP_WAIT_SECS:-5}"
LOCK_WAIT_SECS="${ECHO_PEER_LOCK_WAIT_SECS:-30}"
VERBOSE="${ECHO_PEER_VERBOSE:-}"

# shellcheck source=_echo_peer_lib.sh
. "$MCP_DIR/_echo_peer_lib.sh"

LOCK_HELD=0

cleanup() {
    if [[ "$LOCK_HELD" -eq 1 ]]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        LOCK_HELD=0
    fi
}
trap cleanup EXIT

die() {
    echo "stop_echo_peer.sh: ERROR: $*" >&2
    exit 1
}

# Silent on no-op unless ECHO_PEER_VERBOSE is set (codex Round 13 Z8).
info_noop() {
    if [[ -n "$VERBOSE" ]]; then
        echo "$*"
    fi
}

acquire_lock() {
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [[ "$waited" -ge "$LOCK_WAIT_SECS" ]]; then
            die "could not acquire lock $LOCK_DIR within ${LOCK_WAIT_SECS}s"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    LOCK_HELD=1
}

# CRITICAL (codex Round 13 Z4): acquire the lock BEFORE checking whether
# echo_peer.json exists. If we early-exit on missing json without taking the
# lock, a concurrent `ensure` that is mid-launch (peer spawned, json not yet
# written) will be reported as "nothing to stop" — the shared-lock contract
# would be broken and the fixture would remain running after a "stop".
acquire_lock

if [[ ! -f "$JSON_FILE" ]]; then
    info_noop "OK: nothing to stop (no $JSON_FILE)"
    exit 0
fi

pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE" 2>/dev/null || true)"
start_time="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("start_time",""))' "$JSON_FILE" 2>/dev/null || true)"
cmdline="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cmdline",""))' "$JSON_FILE" 2>/dev/null || true)"

if [[ -z "$pid" || -z "$start_time" || -z "$cmdline" ]]; then
    echo "WARN: $JSON_FILE missing pid/start_time/cmdline; clearing without signaling" >&2
    rm -f "$JSON_FILE"
    info_noop "OK: stale json removed"
    exit 0
fi

# Single shared "validate triple then stop" path (codex Round 13 Z5). If the
# triple does not validate, the recorded process is gone (or pid was recycled);
# we clear the stale json without signaling anything.
validate_reason="$(_ep_validate_triple "$pid" "$start_time" "$cmdline")"
if [[ "$validate_reason" != "ok" ]]; then
    echo "WARN: recorded peer pid=$pid no longer matches recorded triple (${validate_reason}); clearing stale json without signaling" >&2
    rm -f "$JSON_FILE"
    info_noop "OK: stale json removed"
    exit 0
fi

# Triple matched — stop with grace.
if ! _ep_stop_with_grace "$pid" "$STOP_WAIT_SECS"; then
    rm -f "$JSON_FILE"
    die "pid $pid survived SIGKILL (this should not happen on macOS)"
fi

rm -f "$JSON_FILE"
echo "OK: echo peer stopped (pid=${pid})"
