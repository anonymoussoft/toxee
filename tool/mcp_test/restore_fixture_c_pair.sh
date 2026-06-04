#!/usr/bin/env bash
# Restore the paired_for_e2e Fixture C A/B disk trees into per-instance support
# roots. This intentionally does not launch Toxee; launch_fixture_c_pair.sh can
# call it before starting A and B.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
FIXTURES_DIR="$MCP_DIR/fixtures"
MANIFEST_JSON="${TOXEE_FIXTURE_C_MANIFEST:-$FIXTURES_DIR/paired_for_e2e_manifest.json}"
DEFAULT_RESTORE_ROOT="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/multi_instance"
RESTORE_ROOT="${TOXEE_FIXTURE_C_RESTORE_ROOT:-$DEFAULT_RESTORE_ROOT}"
REPORT_JSON="${TOXEE_FIXTURE_C_RESTORE_REPORT:-$RESTORE_ROOT/fixture_c_pair_restore.json}"

die() {
    echo "restore_fixture_c_pair.sh: $*" >&2
    exit 1
}

[[ -f "$MANIFEST_JSON" ]] || die "manifest missing: $MANIFEST_JSON"
command -v jq >/dev/null 2>&1 || die "jq missing"

fmt_ver="$(jq -r '.format_version // empty' "$MANIFEST_JSON")"
[[ "$fmt_ver" == "1" ]] || die "unsupported manifest format_version=$fmt_ver"

if [[ "$(uname -s)" == "Darwin" ]]; then
    if ! jq -e '.supported_platforms | index("macos")' "$MANIFEST_JSON" >/dev/null; then
        die "manifest does not support macos"
    fi
fi

mkdir -p "$RESTORE_ROOT"

restore_instance() {
    local name="$1"
    local fixture_dir tox_id friend_id prefix src dest profile_file history_file
    fixture_dir="$(jq -r --arg n "$name" '.instances[$n].fixture_dir // empty' "$MANIFEST_JSON")"
    tox_id="$(jq -r --arg n "$name" '.instances[$n].tox_id // empty' "$MANIFEST_JSON")"
    friend_id="$(jq -r --arg n "$name" '.instances[$n].friend_tox_id // empty' "$MANIFEST_JSON")"
    [[ -n "$fixture_dir" ]] || die "manifest missing instances.$name.fixture_dir"
    [[ -n "$tox_id" ]] || die "manifest missing instances.$name.tox_id"
    [[ -n "$friend_id" ]] || die "manifest missing instances.$name.friend_tox_id"
    prefix="${tox_id:0:16}"
    src="$FIXTURES_DIR/$fixture_dir"
    dest="$RESTORE_ROOT/$name"
    profile_file="$dest/profiles/p_${prefix}/tox_profile.tox"
    history_file="$dest/account_data/${prefix}/chat_history/${friend_id}.json"

    [[ -d "$src" ]] || die "fixture source missing for $name: $src"
    rm -rf "$dest"
    mkdir -p "$dest"
    cp -a "$src/." "$dest/"
    [[ -f "$profile_file" ]] || die "$name restore missing profile: $profile_file"
    [[ -f "$history_file" ]] || die "$name restore missing chat history: $history_file"
}

restore_instance A
restore_instance B

# Hygiene: NGC group state lives in the persisted SharedPreferences
# `groups_list` / `group_chat_id_*` keys, NOT the app-support tree the restore
# resets above. Those keys survive across runs (the app is sandboxed but writes
# to the NON-sandboxed global plist, so the launcher's `defaults delete` + HOME
# overrides miss them), so the local NGC group ids climb (tox_1..tox_N) and
# stale dead groups add DHT contention that can depress two-process peer
# discovery. Scrub the test-prefixed group keys directly so every run starts
# from zero known groups. Scoped to the `toxee_a.`/`toxee_b.` multi-instance
# prefixes — a real user's prefs (no such prefix) are untouched.
for plist in \
    "$HOME/Library/Preferences/com.toxee.app.plist" \
    "$HOME/Library/Containers/com.toxee.app/Data/Library/Preferences/com.toxee.app.plist"; do
    [[ -f "$plist" ]] || continue
    /usr/bin/python3 - "$plist" <<'PY'
import plistlib, sys
p = sys.argv[1]
try:
    with open(p, 'rb') as f:
        d = plistlib.load(f)
except Exception:
    sys.exit(0)
test_prefixes = ('toxee_a.', 'toxee_b.')
removed = [
    k for k in list(d)
    if k.startswith(test_prefixes)
    and ('groups_list' in k or 'group_chat_id' in k)
]
for k in removed:
    del d[k]
if removed:
    with open(p, 'wb') as f:
        plistlib.dump(d, f)
    print(f'  scrubbed {len(removed)} stale test group pref(s) from {p}')
PY
done
killall cfprefsd >/dev/null 2>&1 || true

/usr/bin/python3 - "$MANIFEST_JSON" "$REPORT_JSON" "$RESTORE_ROOT" <<'PY'
import json
import os
import sys
from datetime import datetime, timezone

manifest_path, report_path, restore_root = sys.argv[1:4]
with open(manifest_path, encoding="utf-8") as f:
    manifest = json.load(f)

instances = {}
for name, data in manifest["instances"].items():
    tox_id = data["tox_id"]
    prefix = tox_id[:16]
    dest = os.path.join(restore_root, name)
    profile = os.path.join(dest, "profiles", f"p_{prefix}", "tox_profile.tox")
    history = os.path.join(
        dest,
        "account_data",
        prefix,
        "chat_history",
        f"{data['friend_tox_id']}.json",
    )
    instances[name] = {
        "tox_id": tox_id,
        "nickname": data["nickname"],
        "friend_tox_id": data["friend_tox_id"],
        "support_dir": dest,
        "profile_file": profile,
        "history_file": history,
        "restored": os.path.exists(profile) and os.path.exists(history),
    }

doc = {
    "format_version": 1,
    "restored_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "manifest": manifest_path,
    "restore_root": restore_root,
    "instances": instances,
}
os.makedirs(os.path.dirname(report_path), exist_ok=True)
tmp = report_path + ".tmp"
with open(tmp, "w", encoding="utf-8") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
os.replace(tmp, report_path)
PY

echo "OK: restored Fixture C paired fixture"
echo "restore root: $RESTORE_ROOT"
echo "report: $REPORT_JSON"
