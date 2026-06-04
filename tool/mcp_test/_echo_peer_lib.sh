#!/usr/bin/env bash
# Echo peer fixture — Phase 3 shared helpers.
#
# Internal helper, NOT a CLI entry point (hence leading underscore). Sourced by
# ensure_echo_peer.sh and stop_echo_peer.sh so they apply identical
# "validate triple then stop" semantics.
#
# Symbols exported:
#   _ep_normalize_args     — collapse whitespace for safe argv comparison
#   _ep_ps_lstart          — read `ps -o lstart=` for a pid (or empty)
#   _ep_ps_args            — read `ps -o args=` for a pid (or empty)
#   _ep_validate_triple    — true iff pid+lstart+cmdline match recorded values
#   _ep_stop_with_grace    — SIGTERM, wait grace_secs, SIGKILL fallback
#   _ep_triple_validate_then_stop
#                          — only stop if triple still validates
#
# Each function returns 0 on success, non-zero on logical failure; they do
# NOT call exit. Callers decide policy (warn vs die vs continue).
#
# Style: no `set -euo pipefail` here — the sourcing script owns that. We never
# assume the caller has nounset on, but we also don't rely on unset vars.
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md, codex Round 13 findings Z5/Z6.

# Collapse all whitespace runs to single spaces, strip leading/trailing.
# Used to compare ps argv against recorded cmdline without falsely failing on
# ps re-padding output under concurrent load.
_ep_normalize_args() {
    # Read from $1 (string arg). Using printf so we don't lose leading spaces
    # before normalization.
    printf '%s' "${1:-}" | awk '{$1=$1; print}'
}

# Echo `ps -o lstart=` for $1; empty string if pid is dead.
_ep_ps_lstart() {
    local pid="$1"
    ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# Echo `ps -o args=` for $1; empty string if pid is dead.
_ep_ps_args() {
    local pid="$1"
    ps -p "$pid" -o args= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

# _ep_validate_triple <pid> <expected_lstart> <expected_cmdline>
# Returns 0 if all three match the live process; 1 otherwise.
# Outputs a single-line diagnostic reason on FD 1 (caller can ignore).
_ep_validate_triple() {
    local pid="${1:-}"
    local expected_lstart="${2:-}"
    local expected_cmdline="${3:-}"
    if [[ -z "$pid" || -z "$expected_lstart" || -z "$expected_cmdline" ]]; then
        echo "missing_inputs"
        return 1
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        echo "pid_dead"
        return 1
    fi
    local live_lstart live_args norm_live norm_expected
    live_lstart="$(_ep_ps_lstart "$pid")"
    live_args="$(_ep_ps_args "$pid")"
    if [[ -z "$live_lstart" || -z "$live_args" ]]; then
        echo "ps_empty"
        return 1
    fi
    if [[ "$live_lstart" != "$expected_lstart" ]]; then
        echo "lstart_mismatch"
        return 1
    fi
    norm_live="$(_ep_normalize_args "$live_args")"
    norm_expected="$(_ep_normalize_args "$expected_cmdline")"
    # Strict normalized equality. Wrapper variance (e.g. nohup-prefixed) is
    # only acceptable if the recorded cmdline ITSELF proves the wrapper —
    # i.e. recorded already contains the wrapper, so strict equality holds.
    if [[ "$norm_live" != "$norm_expected" ]]; then
        echo "cmdline_mismatch"
        return 1
    fi
    echo "ok"
    return 0
}

# _ep_stop_with_grace <pid> <grace_secs>
# SIGTERM the pid, wait up to grace_secs, then SIGKILL if still alive.
# Returns 0 if the process is no longer alive at the end; 1 if it survived
# even SIGKILL (should not happen on macOS but we report it honestly).
# Safe to call on a pid that is already dead (no-op success).
_ep_stop_with_grace() {
    local pid="${1:-}"
    local grace_secs="${2:-5}"
    if [[ -z "$pid" ]]; then
        return 0
    fi
    if ! kill -0 "$pid" 2>/dev/null; then
        return 0
    fi
    kill -TERM "$pid" 2>/dev/null || true
    local waited=0
    while [[ "$waited" -lt "$grace_secs" ]] && kill -0 "$pid" 2>/dev/null; do
        sleep 1
        waited=$((waited + 1))
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill -KILL "$pid" 2>/dev/null || true
        sleep 1
    fi
    if kill -0 "$pid" 2>/dev/null; then
        return 1
    fi
    return 0
}

# _ep_triple_validate_then_stop <pid> <expected_lstart> <expected_cmdline> <grace_secs>
# Validates the triple, and ONLY if it matches, applies SIGTERM/SIGKILL.
# Returns 0 if the process was either (a) successfully stopped, or
# (b) safely skipped because the triple did not validate (recorded peer is
# already gone — recycled pid case, don't signal anyone unrelated).
# Returns 1 if the triple validated but the process survived stop.
_ep_triple_validate_then_stop() {
    local pid="${1:-}"
    local expected_lstart="${2:-}"
    local expected_cmdline="${3:-}"
    local grace_secs="${4:-5}"
    local reason
    reason="$(_ep_validate_triple "$pid" "$expected_lstart" "$expected_cmdline")"
    if [[ "$reason" != "ok" ]]; then
        # Recorded process is gone (or never matched). Safe to skip; caller
        # is expected to clean up the json without signaling.
        return 0
    fi
    _ep_stop_with_grace "$pid" "$grace_secs"
}
