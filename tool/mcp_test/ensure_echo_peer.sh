#!/usr/bin/env bash
# Echo peer fixture — Phase 3 daemon ensure (idempotent).
#
# Brings up the echo peer in daemon mode (detached, persistent across script
# invocations) and writes tool/mcp_test/echo_peer.json describing the running
# process. Subsequent calls validate the recorded process is still the SAME
# process (via the pid+start_time+cmdline triple — see codex Round 8 P2) and
# reuse the cached state instead of relaunching.
#
# Concurrent invocations are mediated by an mkdir-based lock
# (tool/mcp_test/.echo_peer.lock); on POSIX filesystems mkdir is atomic, so we
# get the lock semantics we need without `flock` (which is not on stock
# macOS).
#
# This script does NOT EXIT-trap the peer (the peer must outlive the script).
# It DOES EXIT-trap the lock dir for any trap-covered exit path (normal exit,
# SIGTERM/SIGINT, internal `die`, etc.). Hard-crash paths that bypass the trap
# entirely (SIGKILL via `kill -9`, host power loss, OOM killer) DO leave a
# stale `.echo_peer.lock` and possibly a pre-JSON launched peer; mkdir-locks
# have no automatic stale-recovery. Manual cleanup: `rm -rf
# tool/mcp_test/.echo_peer.lock && pgrep -f echo_peer_src/build/echo_peer |
# xargs -r kill`. This trade-off is accepted in v2.3 — a supervisor or
# advisory-lock-based daemon would defeat the simplicity goal.
# It ALSO EXIT-traps the just-launched peer with a 5s grace + SIGKILL if any
# post-launch validation step fails (codex Round 13 Z7), so a failed `ensure`
# (via the normal trap-covered paths) never leaves a half-started daemon
# behind for the next `ensure` to double.
#
# Env overrides:
#   ECHO_PEER_LOCK_WAIT_SECS   (default 30) seconds to wait for the lock dir
#   ECHO_PEER_START_TIMEOUT_SECS (default 30) seconds to wait for ID emission
#   ECHO_PEER_BIN              path to peer binary
#                              (default tool/mcp_test/echo_peer_src/build/echo_peer)
#   ECHO_PEER_STATE_DIR_BASE   path to state dir parent
#                              (default tool/mcp_test/echo_peer_state)
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md "Phase 3 — Daemon + foreground helpers".
set -euo pipefail

# -------------- Configuration ----------------------------------------------
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
PEER_BIN="${ECHO_PEER_BIN:-$MCP_DIR/echo_peer_src/build/echo_peer}"
STATE_DIR_BASE="${ECHO_PEER_STATE_DIR_BASE:-$MCP_DIR/echo_peer_state}"
JSON_FILE="$MCP_DIR/echo_peer.json"
STDOUT_LOG="$MCP_DIR/echo_peer.stdout.log"
STDERR_LOG="$MCP_DIR/echo_peer.stderr.log"
LOCK_DIR="$MCP_DIR/.echo_peer.lock"

LOCK_WAIT_SECS="${ECHO_PEER_LOCK_WAIT_SECS:-30}"
START_TIMEOUT_SECS="${ECHO_PEER_START_TIMEOUT_SECS:-30}"
LAUNCH_FAIL_GRACE_SECS="${ECHO_PEER_LAUNCH_FAIL_GRACE_SECS:-5}"
POST_START_STABILIZE_SECS="${ECHO_PEER_POST_START_STABILIZE_SECS:-2}"

ID_PREFIX='ECHO_PEER_TOX_ID:'

# shellcheck source=_echo_peer_lib.sh
. "$MCP_DIR/_echo_peer_lib.sh"

LOCK_HELD=0
# Per-launch pid of the peer we spawned this run. Set right after `nohup ... &`,
# cleared after we've successfully written the json (so the EXIT trap stops
# trying to reap a peer that is now considered live and owned by the json).
LAUNCHED_PID=""

cleanup() {
    # If we spawned a peer this run and have not yet committed it via json,
    # tear it down with grace before releasing the lock — codex Round 13 Z7.
    if [[ -n "$LAUNCHED_PID" ]]; then
        _ep_stop_with_grace "$LAUNCHED_PID" "$LAUNCH_FAIL_GRACE_SECS" || true
        LAUNCHED_PID=""
    fi
    if [[ "$LOCK_HELD" -eq 1 ]]; then
        rmdir "$LOCK_DIR" 2>/dev/null || true
        LOCK_HELD=0
    fi
}
trap cleanup EXIT

# -------------- Helpers ----------------------------------------------------
die() {
    echo "ensure_echo_peer.sh: ERROR: $*" >&2
    exit 1
}

acquire_lock() {
    local waited=0
    while ! mkdir "$LOCK_DIR" 2>/dev/null; do
        if [[ "$waited" -ge "$LOCK_WAIT_SECS" ]]; then
            die "could not acquire lock $LOCK_DIR within ${LOCK_WAIT_SECS}s (another ensure_echo_peer.sh in flight? remove the dir if stale)"
        fi
        sleep 1
        waited=$((waited + 1))
    done
    LOCK_HELD=1
}

# Validate that the triple in $JSON_FILE still describes the same live
# process. Echoes "ok" or a reason string; exit code is always 0.
# Uses the shared _ep_validate_triple (codex Round 13 Z5/Z6).
validate_recorded_triple() {
    if [[ ! -f "$JSON_FILE" ]]; then
        echo "no_json"
        return 0
    fi
    local pid start_time cmdline
    pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE" 2>/dev/null || true)"
    start_time="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("start_time",""))' "$JSON_FILE" 2>/dev/null || true)"
    cmdline="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cmdline",""))' "$JSON_FILE" 2>/dev/null || true)"

    if [[ -z "$pid" || -z "$start_time" || -z "$cmdline" ]]; then
        echo "json_unparseable"
        return 0
    fi
    local reason
    reason="$(_ep_validate_triple "$pid" "$start_time" "$cmdline" || true)"
    echo "$reason"
    return 0
}

# Atomic JSON write: tmpfile + mv -f.
write_json_atomic() {
    local pid="$1"
    local start_time="$2"
    local cmdline="$3"
    local state_dir="$4"
    local peer_id="$5"
    local started_at
    started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

    local tmp
    tmp="$(mktemp "${JSON_FILE}.tmp.XXXXXX")"
    /usr/bin/python3 - "$tmp" "$pid" "$start_time" "$cmdline" "$state_dir" "$peer_id" "$STDOUT_LOG" "$STDERR_LOG" "$started_at" <<'PY'
import json, sys
tmp, pid, start_time, cmdline, state_dir, peer_id, stdout_log, stderr_log, started_at = sys.argv[1:10]
doc = {
    "format_version": 1,
    "pid": int(pid),
    "start_time": start_time,
    "cmdline": cmdline,
    "state_dir": state_dir,
    "peer_id": peer_id,
    "stdout_log": stdout_log,
    "stderr_log": stderr_log,
    "started_at": started_at,
}
with open(tmp, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY
    mv -f "$tmp" "$JSON_FILE"
}

# Read the peer_id from $JSON_FILE for cached-reuse reporting.
cached_peer_id() {
    /usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("peer_id",""))' "$JSON_FILE" 2>/dev/null || true
}

# -------------- Pre-flight -------------------------------------------------
[[ -x "$PEER_BIN" ]] || die "peer binary not found or not executable: $PEER_BIN"

mkdir -p "$STATE_DIR_BASE"

# Acquire the lock BEFORE touching the json, so concurrent ensures serialize.
acquire_lock

# -------------- Fast path: validate cached state ---------------------------
validation="$(validate_recorded_triple)"
if [[ "$validation" == "ok" ]]; then
    peer_id="$(cached_peer_id)"
    pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE")"
    echo "OK: echo peer ready (pid=${pid}, peer_id=${peer_id:0:16}...) [cached]"
    echo "json: $JSON_FILE"
    exit 0
fi

# Cached state is invalid; clean it up before relaunch. We can't run
# stop_echo_peer.sh recursively (it would try to take the same lock); use the
# shared "validate triple then stop" helper so the safety contract is
# identical to stop_echo_peer.sh (codex Round 13 Z5).
if [[ -f "$JSON_FILE" ]]; then
    stale_pid="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("pid",""))' "$JSON_FILE" 2>/dev/null || true)"
    stale_start="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("start_time",""))' "$JSON_FILE" 2>/dev/null || true)"
    stale_cmdline="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cmdline",""))' "$JSON_FILE" 2>/dev/null || true)"
    if [[ -n "$stale_pid" && -n "$stale_start" && -n "$stale_cmdline" ]]; then
        # Triple-validate before signaling. Skips quietly if pid recycled.
        _ep_triple_validate_then_stop \
            "$stale_pid" "$stale_start" "$stale_cmdline" "$LAUNCH_FAIL_GRACE_SECS" || true
    fi
    rm -f "$JSON_FILE"
fi

# -------------- Fresh launch -----------------------------------------------
# Truncate logs so the ID line we wait for is fresh.
: > "$STDOUT_LOG"
: > "$STDERR_LOG"

# State dir: project-local, persistent across script invocations.
STATE_DIR="$STATE_DIR_BASE"
mkdir -p "$STATE_DIR"

# Detached launch. `nohup` so the child survives shell hangup. We deliberately
# do NOT use `setsid` (not portable to macOS without coreutils) — nohup +
# stdin redirected from /dev/null is enough for our daemon use case.
ECHO_PEER_STATE_DIR="$STATE_DIR" nohup "$PEER_BIN" \
    >"$STDOUT_LOG" 2>"$STDERR_LOG" </dev/null &
PEER_PID=$!
# From this point on, any failure exit must reap the launched peer (codex
# Round 13 Z7). The EXIT trap handles it via _ep_stop_with_grace.
LAUNCHED_PID="$PEER_PID"

# Poll for the ID line.
peer_id=""
elapsed=0
poll_ms=200
while [[ -z "$peer_id" ]]; do
    if ! kill -0 "$PEER_PID" 2>/dev/null; then
        # Peer exited on its own; nothing to reap.
        LAUNCHED_PID=""
        die "peer exited before emitting ID; see $STDERR_LOG"
    fi
    if [[ -f "$STDOUT_LOG" ]]; then
        # Last matching line (defensive: tolerate noise before the prefix).
        line="$(grep -E "^${ID_PREFIX}" "$STDOUT_LOG" | tail -n 1 || true)"
        if [[ -n "$line" ]]; then
            peer_id="${line#${ID_PREFIX} }"
            peer_id="${peer_id## }"
            break
        fi
    fi
    if [[ "$elapsed" -ge "$((START_TIMEOUT_SECS * 1000))" ]]; then
        # Let the EXIT trap apply the 5s grace + SIGKILL fallback so we never
        # leak a half-started daemon (codex Round 13 Z7).
        die "timed out after ${START_TIMEOUT_SECS}s waiting for '${ID_PREFIX}' in $STDOUT_LOG (stderr: $STDERR_LOG)"
    fi
    sleep "$(awk -v ms="$poll_ms" 'BEGIN{printf "%.3f", ms/1000}')"
    elapsed=$((elapsed + poll_ms))
done

# A process that emits its ID and then dies immediately is not a usable echo
# harness; committing that PID to echo_peer.json makes downstream MCP runs burn
# minutes on impossible echo waits. Hold the process for a short stabilization
# window before we publish the json so "booted enough to print" is not mistaken
# for "ready enough to serve scenarios".
if [[ "$POST_START_STABILIZE_SECS" -gt 0 ]]; then
    sleep "$POST_START_STABILIZE_SECS"
    if ! kill -0 "$PEER_PID" 2>/dev/null; then
        LAUNCHED_PID=""
        die "peer exited ${POST_START_STABILIZE_SECS}s after ID emission; refusing to publish stale json (stderr: $STDERR_LOG)"
    fi
fi

# Capture the triple from the now-running peer.
start_time="$(_ep_ps_lstart "$PEER_PID")"
cmdline="$(_ep_ps_args "$PEER_PID")"
if [[ -z "$start_time" || -z "$cmdline" ]]; then
    # EXIT trap will reap.
    die "could not capture ps triple for pid $PEER_PID (peer died?)"
fi

write_json_atomic "$PEER_PID" "$start_time" "$cmdline" "$STATE_DIR" "$peer_id"

# Json committed — the peer is now owned by the recorded state, NOT by this
# script's EXIT trap. Clear LAUNCHED_PID so cleanup() leaves it running.
LAUNCHED_PID=""

echo "OK: echo peer ready (pid=${PEER_PID}, peer_id=${peer_id:0:16}...)"
echo "json: $JSON_FILE"
