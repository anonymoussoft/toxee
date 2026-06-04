#!/usr/bin/env bash
# Shared helpers for the disposable Fixture C multi-instance spike harness.
#
# This library intentionally mirrors the echo-peer helpers' "record a process
# triple and only signal the recorded process" discipline so repeated spike
# runs do not kill unrelated Toxee processes.

_mi_normalize_args() {
    printf '%s' "${1:-}" | awk '{$1=$1; print}'
}

_mi_ps_lstart() {
    local pid="$1"
    ps -p "$pid" -o lstart= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

_mi_ps_args() {
    local pid="$1"
    ps -p "$pid" -o args= 2>/dev/null | sed 's/^ *//;s/ *$//'
}

_mi_pids_for_executable() {
    local executable="$1"
    /usr/bin/python3 - "$executable" <<'PY'
import subprocess
import sys

executable = sys.argv[1]
try:
    out = subprocess.check_output(["ps", "ax", "-o", "pid=", "-o", "args="], text=True)
except Exception:
    sys.exit(0)
for line in out.splitlines():
    stripped = line.strip()
    if not stripped:
        continue
    pid, _, args = stripped.partition(" ")
    args = args.strip()
    if args == executable or args.startswith(executable + " "):
        print(pid)
PY
}

_mi_new_pids_since_baseline() {
    local executable="$1"
    local baseline="${2:-}"
    local current
    current="$(_mi_pids_for_executable "$executable")"
    /usr/bin/python3 - "$baseline" "$current" <<'PY'
import sys

baseline = {line.strip() for line in sys.argv[1].splitlines() if line.strip()}
current = [line.strip() for line in sys.argv[2].splitlines() if line.strip()]
for pid in current:
    if pid not in baseline:
        print(pid)
PY
}

_mi_validate_triple() {
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
    live_lstart="$(_mi_ps_lstart "$pid")"
    live_args="$(_mi_ps_args "$pid")"
    if [[ -z "$live_lstart" || -z "$live_args" ]]; then
        echo "ps_empty"
        return 1
    fi
    if [[ "$live_lstart" != "$expected_lstart" ]]; then
        echo "lstart_mismatch"
        return 1
    fi
    norm_live="$(_mi_normalize_args "$live_args")"
    norm_expected="$(_mi_normalize_args "$expected_cmdline")"
    if [[ "$norm_live" != "$norm_expected" ]]; then
        echo "cmdline_mismatch"
        return 1
    fi
    echo "ok"
    return 0
}

_mi_stop_with_grace() {
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
