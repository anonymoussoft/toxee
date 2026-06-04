#!/usr/bin/env bash
# Launch A + B for the Fixture C multi-instance spike.
#
# Scope for this disposable harness:
#   - start A and B as separate OS processes
#   - record different VM URIs / ws URIs
#   - report whether HOME override yielded per-instance support logs
#   - provide a single teardown entry point
#
# It does NOT yet drive friend-add / ping-pong. The emitted pair.json is the
# hand-off contract for a future MCP step.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNTIME_ROOT="${TOXEE_MULTI_RUNTIME_ROOT:-$MCP_DIR/.multi_instance_runtime}"
PAIR_JSON="$RUNTIME_ROOT/pair.json"
APP_BUNDLE="${TOXEE_APP_BUNDLE:-$REPO_ROOT/build/macos/Build/Products/Debug/Toxee.app}"
COPIES_DIR="$RUNTIME_ROOT/app_copies"
APP_B_COPY="$COPIES_DIR/ToxeeB.app"
VM_PROBE_DART="$MCP_DIR/probe_vm_service.dart"
CONTAINER_MULTI_ROOT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/multi_instance"
FIXTURE_RESTORE_MODE="${TOXEE_FIXTURE_C_RESTORE:-}"
FIXTURE_RESTORE_REPORT="$CONTAINER_MULTI_ROOT/fixture_c_pair_restore.json"

mkdir -p "$RUNTIME_ROOT"
mkdir -p "$COPIES_DIR"
rm -rf "$RUNTIME_ROOT/A" "$RUNTIME_ROOT/B"
rm -rf "$CONTAINER_MULTI_ROOT/A" "$CONTAINER_MULTI_ROOT/B"
# Disposable spike harness: clear the shared macOS defaults domain so both
# instances start from a blank login state. Without this, a previous run's
# shared `account_list` can turn the register page into a saved-account page
# before the pair driver ever starts.
defaults delete com.toxee.app >/dev/null 2>&1 || true
killall cfprefsd >/dev/null 2>&1 || true

if [[ "$FIXTURE_RESTORE_MODE" == "paired" || "$FIXTURE_RESTORE_MODE" == "paired_for_e2e" ]]; then
    TOXEE_FIXTURE_C_RESTORE_ROOT="$CONTAINER_MULTI_ROOT" \
        "$MCP_DIR/restore_fixture_c_pair.sh"
fi

"$MCP_DIR/launch_toxee_instance.sh" A
A_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/A/instance.json")"
dart run "$VM_PROBE_DART" "$A_WS_URI"
# Empirically, launching both instances from the exact same .app path leaves the
# direct-launch VM service attach path unhealthy (`Connection closed before full
# header was received`). A physical copy for B avoids that collision and keeps
# the rest of the harness unchanged.
rm -rf "$APP_B_COPY"
cp -R "$APP_BUNDLE" "$APP_B_COPY"
TOXEE_APP_BUNDLE="$APP_B_COPY" "$MCP_DIR/launch_toxee_instance.sh" B
B_WS_URI="$(jq -r '.ws_uri' "$RUNTIME_ROOT/B/instance.json")"
dart run "$VM_PROBE_DART" "$A_WS_URI"
dart run "$VM_PROBE_DART" "$B_WS_URI"

/usr/bin/python3 - "$RUNTIME_ROOT/A/instance.json" "$RUNTIME_ROOT/B/instance.json" "$PAIR_JSON" "$FIXTURE_RESTORE_MODE" "$FIXTURE_RESTORE_REPORT" <<'PY'
import json
import os
import sys

a_file, b_file, out_file, fixture_restore_mode, fixture_restore_report = sys.argv[1:6]
with open(a_file) as fa:
    a = json.load(fa)
with open(b_file) as fb:
    b = json.load(fb)
restore = None
if fixture_restore_mode in {"paired", "paired_for_e2e"} and os.path.exists(fixture_restore_report):
    with open(fixture_restore_report) as fr:
        restore = json.load(fr)

doc = {
    "format_version": 1,
    "instances": {"A": a, "B": b},
    "fixture_restore": {
        "mode": fixture_restore_mode or None,
        "report": fixture_restore_report if restore is not None else None,
        "restored": restore,
    },
    "checks": {
        "distinct_pids": a["pid"] != b["pid"],
        "distinct_ws_uris": a["ws_uri"] != b["ws_uri"],
        "distinct_vm_ports": a["vm_uri"] != b["vm_uri"],
        "home_override_dirs_differ": a["home_override_dir"] != b["home_override_dir"],
        "app_support_log_exists_in_a_home": a["app_support_log_exists"],
        "app_support_log_exists_in_b_home": b["app_support_log_exists"],
    },
}
with open(out_file, "w") as f:
    json.dump(doc, f, indent=2)
    f.write("\n")
PY

echo "OK: launched Fixture C pair"
echo "pair json: $PAIR_JSON"
echo "A ws_uri: $(jq -r '.instances.A.ws_uri' "$PAIR_JSON")"
echo "B ws_uri: $(jq -r '.instances.B.ws_uri' "$PAIR_JSON")"
