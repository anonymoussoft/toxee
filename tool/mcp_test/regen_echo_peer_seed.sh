#!/usr/bin/env bash
# Echo peer fixture — Phase 4 one-shot seed generator.
#
# Boots a fresh Toxee account, befriends the echo peer, exchanges 3 ping/pong
# pairs, then snapshots the resulting state (Tox profile + account_data +
# NSUserDefaults flutter.* keys) into a per-machine tarball under
# tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst.
#
# The committed sibling at tool/mcp_test/fixtures/echo_peer_seeded_manifest.json
# is a copy of the in-tar manifest for git-diff visibility; the in-tar copy is
# the authoritative one the restore tool reads.
#
# macOS ONLY in v2.3. Restore tool gates on manifest.supported_platforms.
#
# Env overrides:
#   REGEN_NO_DRIVE        unset to drive UI via marionette; set to skip UI
#                         driving and emit a structural-only fixture (smoke
#                         testing path — produced fixture won't reflect a real
#                         logged-in account, but exercises the file/Prefs
#                         capture and pack/unpack layers).
#   REGEN_NICKNAME        default echo_seeded_test
#   REGEN_VM_URI_TIMEOUT  default 180 seconds to wait for the VM service URI
#                         file to appear after launch (cold builds are slow).
#   REGEN_DRIVE_TIMEOUT   default 600 seconds to allow the driver to complete.
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md "Phase 4 — Hybrid fixture
# model" and §4 "regen_echo_peer_seed.sh — generate snapshot".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
FIXTURES_DIR="$MCP_DIR/fixtures"
CACHE_DIR="$FIXTURES_DIR/.cache"
SIBLING_MANIFEST="$FIXTURES_DIR/echo_peer_seeded_manifest.json"
ECHO_PEER_JSON="$MCP_DIR/echo_peer.json"
DRIVER_DART="$MCP_DIR/_drive_seed.dart"

NICKNAME="${REGEN_NICKNAME:-echo_seeded_test}"
VM_URI_TIMEOUT="${REGEN_VM_URI_TIMEOUT:-180}"
DRIVE_TIMEOUT="${REGEN_DRIVE_TIMEOUT:-600}"

TOXEE_SUPPORT_DIR="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app"
TOXEE_PROFILES_DIR="$TOXEE_SUPPORT_DIR/profiles"
TOXEE_ACCOUNT_DATA_DIR="$TOXEE_SUPPORT_DIR/account_data"
TOXEE_DOMAIN="com.toxee.app"
RUN_LOG="$REPO_ROOT/build/regen_toxee_run.log"

# -------------- TTY colors -------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_GREEN="$(tput setaf 2)"; C_RED="$(tput setaf 1)"; C_YELLOW="$(tput setaf 3)"
    C_DIM="$(tput dim)"; C_RST="$(tput sgr0)"
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_RST=""
fi
info() { printf '%s[regen]%s %s\n' "${C_DIM}" "${C_RST}" "$*"; }
warn() { printf '%s[regen WARN]%s %s\n' "${C_YELLOW}" "${C_RST}" "$*" >&2; }
die() { printf '%s[regen ERROR]%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2; exit 1; }
ok() { printf '%s[regen OK]%s %s\n' "${C_GREEN}" "${C_RST}" "$*"; }

# -------------- Pre-flight -------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "regen is macOS-only in v2.3 (got $(uname -s))"
command -v zstd >/dev/null 2>&1 || die "zstd missing; install with: brew install zstd"
command -v tar  >/dev/null 2>&1 || die "tar missing (should ship with macOS)"
command -v plutil >/dev/null 2>&1 || die "plutil missing (should ship with macOS)"
command -v jq >/dev/null 2>&1 || die "jq missing; install with: brew install jq"
command -v defaults >/dev/null 2>&1 || die "defaults missing (should ship with macOS)"

# Stock macOS does not ship GNU `timeout`; coreutils provides it as `gtimeout`.
# Prefer the plain name (some users symlink), fall back to gtimeout, otherwise
# bail with a brew hint so the failure mode is obvious instead of "command not
# found" mid-drive.
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
    TIMEOUT_CMD="gtimeout"
else
    die "neither 'timeout' nor 'gtimeout' is on PATH; install GNU coreutils: brew install coreutils"
fi
info "using timeout command: $TIMEOUT_CMD"

# Machine id: prefer macOS Hardware UUID, fall back to hostname -s.
machine_id="$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null \
    | awk '/IOPlatformUUID/{print $3}' | tr -d '"' | head -n1 || true)"
if [[ -z "$machine_id" ]]; then
    machine_id="$(hostname -s 2>/dev/null || echo unknown)"
fi
# Sanitize for filename: strip any non [A-Z0-9-_].
machine_id="$(printf '%s' "$machine_id" | tr -c 'A-Za-z0-9_-' '_' | head -c 64)"
info "machine_id=$machine_id"

mkdir -p "$CACHE_DIR"
CACHE_TARBALL="$CACHE_DIR/echo_peer_seeded_${machine_id}.tar.zst"

# -------------- Echo peer ready --------------------------------------------
info "ensuring echo peer is running"
"$MCP_DIR/ensure_echo_peer.sh" >/dev/null
[[ -f "$ECHO_PEER_JSON" ]] || die "ensure_echo_peer.sh did not produce $ECHO_PEER_JSON"
PEER_ID="$(/usr/bin/python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("peer_id",""))' "$ECHO_PEER_JSON")"
[[ -n "$PEER_ID" ]] || die "echo_peer.json has no peer_id"
[[ "${#PEER_ID}" -eq 76 ]] || die "peer_id is not 76 chars (got ${#PEER_ID}: $PEER_ID)"
ok "peer_id=${PEER_ID:0:16}..."

# Ensure we stop the echo peer on exit (after snapshot is packed). We trap
# this here so any failure between now and pack still tears it down.
STOP_PEER_ON_EXIT=1
TOXEE_PID=""
STAGE_DIR=""

cleanup() {
    if [[ -n "$TOXEE_PID" ]] && kill -0 "$TOXEE_PID" 2>/dev/null; then
        warn "Toxee still running on cleanup (pid=$TOXEE_PID); terminating"
        kill -TERM "$TOXEE_PID" 2>/dev/null || true
        sleep 2
        kill -KILL "$TOXEE_PID" 2>/dev/null || true
    fi
    if [[ -n "$STAGE_DIR" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi
    if [[ "$STOP_PEER_ON_EXIT" -eq 1 ]]; then
        "$MCP_DIR/stop_echo_peer.sh" >/dev/null 2>&1 || true
    fi
}
trap cleanup EXIT

# -------------- Wipe toxee state -------------------------------------------
info "wiping toxee state"
pkill -f "Debug/Toxee.app" 2>/dev/null || true
sleep 1
# Defensive escaping; do NOT word-split.
if [[ -d "$TOXEE_PROFILES_DIR" ]]; then
    find "$TOXEE_PROFILES_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
fi
if [[ -d "$TOXEE_ACCOUNT_DATA_DIR" ]]; then
    find "$TOXEE_ACCOUNT_DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
fi
defaults delete "$TOXEE_DOMAIN" 2>/dev/null || true
killall cfprefsd 2>/dev/null || true
ok "state wiped"

# -------------- Launch toxee fresh -----------------------------------------
mkdir -p "$REPO_ROOT/build"
VM_URI_FILE="$REPO_ROOT/build/vm_service_uri.txt"
rm -f "$VM_URI_FILE"

info "launching toxee (MCP_BINDING=marionette) — log at $RUN_LOG"
(
    cd "$REPO_ROOT"
    MCP_BINDING=marionette ./run_toxee.sh > "$RUN_LOG" 2>&1
) &
TOXEE_PID=$!
info "Toxee launcher pid=$TOXEE_PID; waiting up to ${VM_URI_TIMEOUT}s for VM service URI"

# Wait for VM service URI to appear.
elapsed=0
while [[ "$elapsed" -lt "$VM_URI_TIMEOUT" ]]; do
    if [[ -s "$VM_URI_FILE" ]]; then
        WS_URI="$(head -n1 "$VM_URI_FILE")"
        if [[ -n "$WS_URI" ]]; then
            break
        fi
    fi
    if ! kill -0 "$TOXEE_PID" 2>/dev/null; then
        die "toxee launcher exited before VM URI appeared; see $RUN_LOG"
    fi
    sleep 1
    elapsed=$((elapsed + 1))
done
[[ -n "${WS_URI:-}" ]] || die "VM URI not produced within ${VM_URI_TIMEOUT}s; see $RUN_LOG"
ok "WS URI: $WS_URI"

# -------------- Drive via marionette ---------------------------------------
if [[ -n "${REGEN_NO_DRIVE:-}" ]]; then
    warn "REGEN_NO_DRIVE set; skipping marionette driving (structural smoke only)"
    info "Toxee is running; pausing 5s so the app reaches an idle state"
    sleep 5
else
    info "driving UI via marionette (timeout ${DRIVE_TIMEOUT}s)"
    # FATAL on driver failure. Anything less risks shipping a structurally
    # valid but semantically broken fixture into the cache + sibling manifest.
    # If the user wants a structural-only smoke, they should set
    # REGEN_NO_DRIVE=1 explicitly; that path goes through the same invariant
    # gate below, so it will still refuse to pack garbage state.
    if ! (cd "$REPO_ROOT" && \
        "$TIMEOUT_CMD" "${DRIVE_TIMEOUT}s" dart run "$DRIVER_DART" "$WS_URI" "$PEER_ID" "$NICKNAME"); then
        die "marionette driver failed (or Toxee crashed mid-drive); refusing to pack a partial fixture. See $RUN_LOG for app side and stderr above for driver side. Set REGEN_NO_DRIVE=1 only if you intentionally want a structural-only smoke."
    fi
fi

# -------------- Graceful Toxee quit ----------------------------------------
info "asking Toxee to quit (osascript)"
osascript -e 'tell application "Toxee" to quit' 2>/dev/null || true
# Wait for run_toxee.sh wrapper to exit. Bounded loop so we don't hang.
quit_wait=0
while [[ "$quit_wait" -lt 30 ]] && kill -0 "$TOXEE_PID" 2>/dev/null; do
    sleep 1
    quit_wait=$((quit_wait + 1))
done
if kill -0 "$TOXEE_PID" 2>/dev/null; then
    warn "Toxee did not quit gracefully in 30s; SIGTERM-ing the launcher"
    kill -TERM "$TOXEE_PID" 2>/dev/null || true
    sleep 3
    kill -KILL "$TOXEE_PID" 2>/dev/null || true
fi
TOXEE_PID=""
# Also kill any lingering app processes.
pkill -f "Debug/Toxee.app" 2>/dev/null || true
sleep 1
ok "Toxee stopped"

# -------------- Stage capture ----------------------------------------------
STAGE_DIR="$(mktemp -d -t echo_peer_seed_stage)"
mkdir -p "$STAGE_DIR/disk" "$STAGE_DIR/prefs"
info "staging at $STAGE_DIR"

# Disk.
if [[ -d "$TOXEE_PROFILES_DIR" ]]; then
    cp -a "$TOXEE_PROFILES_DIR" "$STAGE_DIR/disk/profiles"
else
    mkdir -p "$STAGE_DIR/disk/profiles"
    warn "no profiles dir at $TOXEE_PROFILES_DIR — empty disk/profiles"
fi
if [[ -d "$TOXEE_ACCOUNT_DATA_DIR" ]]; then
    cp -a "$TOXEE_ACCOUNT_DATA_DIR" "$STAGE_DIR/disk/account_data"
else
    mkdir -p "$STAGE_DIR/disk/account_data"
    warn "no account_data dir at $TOXEE_ACCOUNT_DATA_DIR — empty disk/account_data"
fi

# Prefs export + filter + type-tag.
PLIST_TMP="$STAGE_DIR/prefs_raw.plist"
PREFS_JSON="$STAGE_DIR/prefs/prefs_dump.json"
if defaults export "$TOXEE_DOMAIN" "$PLIST_TMP" 2>/dev/null && [[ -s "$PLIST_TMP" ]]; then
    plutil -convert json -o "$STAGE_DIR/prefs_raw.json" "$PLIST_TMP"
    info "exported NSUserDefaults to JSON"
else
    # Empty domain — produce empty {} for downstream tools.
    echo '{}' > "$STAGE_DIR/prefs_raw.json"
    warn "no Prefs exported from $TOXEE_DOMAIN (empty domain)"
fi
rm -f "$PLIST_TMP"

# Build typed Prefs dump via Python (jq's type detection is too coarse for
# int-vs-double distinction and bool detection from plist-converted JSON).
PREFIX_STRIPPED="flutter."
CAPTURED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
/usr/bin/python3 - "$STAGE_DIR/prefs_raw.json" "$PREFS_JSON" \
    "$PREFIX_STRIPPED" "$CAPTURED_AT" "$TOXEE_DOMAIN" <<'PY'
import json, sys, os
raw_path, out_path, prefix, captured_at, domain = sys.argv[1:6]
with open(raw_path) as f:
    raw = json.load(f)
keys = {}
for full_key, value in raw.items():
    if not full_key.startswith(prefix):
        continue
    short = full_key[len(prefix):]
    if isinstance(value, bool):
        keys[short] = {"type": "bool", "value": value}
    elif isinstance(value, int):
        keys[short] = {"type": "int", "value": value}
    elif isinstance(value, float):
        keys[short] = {"type": "double", "value": value}
    elif isinstance(value, list):
        # Coerce to list of strings (NSArray<NSString*>).
        keys[short] = {"type": "string_list", "value": [str(x) for x in value]}
    elif isinstance(value, str):
        keys[short] = {"type": "string", "value": value}
    else:
        # Skip unknown types but log to stderr.
        sys.stderr.write(f"[regen] WARN: skipping flutter.{short} (unsupported type {type(value).__name__})\n")
doc = {
    "format_version": 1,
    "domain": domain,
    "key_prefix": prefix,
    "captured_at": captured_at,
    "keys": keys,
}
# Atomic write.
tmp = out_path + ".tmp"
with open(tmp, "w") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
os.rename(tmp, out_path)
print(len(keys))
PY
KEY_COUNT="$(jq '.keys | length' "$PREFS_JSON")"
ok "captured $KEY_COUNT flutter.* prefs keys"
rm -f "$STAGE_DIR/prefs_raw.json"

# Derive prefix from current_account_tox_id (preferred) or first 16 chars of peer_id (fallback).
PREFIX="$(jq -r '.keys["current_account_tox_id"].value // ""' "$PREFS_JSON" | head -c 16)"
if [[ -z "$PREFIX" ]]; then
    PREFIX="$(printf '%s' "$PEER_ID" | head -c 16)"
    warn "no current_account_tox_id in Prefs; using peer_id prefix=$PREFIX as fallback"
fi

# Repo versions.
TOXEE_VERSION="$(cd "$REPO_ROOT" && git describe --tags --always --dirty 2>/dev/null || echo unknown)"
TIM2TOX_SHA="$(cd "$REPO_ROOT/third_party/tim2tox" && git rev-parse HEAD 2>/dev/null || echo unknown)"

# Manifest.
MANIFEST_PATH="$STAGE_DIR/manifest.json"
MANIFEST_TMP="$MANIFEST_PATH.tmp"
/usr/bin/python3 - "$MANIFEST_TMP" "$CAPTURED_AT" "$TOXEE_VERSION" \
    "$TIM2TOX_SHA" "$PEER_ID" "$PREFIX" "$KEY_COUNT" <<'PY'
import json, sys, os
tmp, created_at, toxee_version, tim2tox_sha, peer_id, prefix, key_count = sys.argv[1:8]
doc = {
    "format_version": 1,
    "created_at": created_at,
    "toxee_version": toxee_version,
    "tim2tox_sha": tim2tox_sha,
    "peer_id": peer_id,
    "peer_id_format": "address76",
    "prefix": prefix,
    "key_count_expected": int(key_count),
    "min_zstd_version": "1.5.0",
    "supported_platforms": ["macos"],
    "tar_layout": {
        "disk/profiles/": "Tox profile blobs; restore to ~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/",
        "disk/account_data/": "Chat history + friend list + avatars; restore to .../account_data/",
        "prefs/prefs_dump.json": "Serialized NSUserDefaults flutter.* keys; restore via defaults write loop",
        "manifest.json": "Self-describing manifest; sibling-copy at tool/mcp_test/fixtures/echo_peer_seeded_manifest.json for git-diff visibility",
    },
}
with open(tmp, "w") as f:
    json.dump(doc, f, indent=2, sort_keys=True)
    f.write("\n")
PY
mv -f "$MANIFEST_TMP" "$MANIFEST_PATH"
ok "manifest written"

# -------------- Invariant validation (pre-pack) ----------------------------
# Validate the staged SNAPSHOT (not live state) before we overwrite the cache
# tarball + sibling manifest. Catches the "driver said OK but actually didn't
# log in / didn't befriend" failure mode, and protects REGEN_NO_DRIVE=1 from
# packing a truly empty/freshly-wiped state.
info "validating snapshot invariants before packing"

# I1: profiles/p_<prefix>/ exists and is non-empty (Tox profile blob present).
PROFILE_DIR="$STAGE_DIR/disk/profiles/p_${PREFIX}"
if [[ ! -d "$PROFILE_DIR" ]]; then
    die "invariant I1 failed: expected profile dir $PROFILE_DIR missing from snapshot (driver did not produce a seeded account)"
fi
profile_file_count="$(find "$PROFILE_DIR" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "${profile_file_count:-0}" -lt 1 ]]; then
    die "invariant I1 failed: $PROFILE_DIR has no files (expected at least the Tox profile blob)"
fi

# I2: account_data/<prefix>/ exists in the snapshot.
ACCOUNT_DIR="$STAGE_DIR/disk/account_data/${PREFIX}"
if [[ ! -d "$ACCOUNT_DIR" ]]; then
    die "invariant I2 failed: expected account_data dir $ACCOUNT_DIR missing from snapshot"
fi

# I3-I5: Prefs invariants. Validate via python so we get one consistent
# parse + clear error messages.
/usr/bin/python3 - "$PREFS_JSON" "$PREFIX" "$PEER_ID" <<'PY' || die "Prefs invariants failed (see errors above); refusing to pack"
import json, sys
prefs_path, prefix, peer_id = sys.argv[1:4]
try:
    with open(prefs_path) as f:
        doc = json.load(f)
except Exception as e:
    sys.stderr.write(f"[regen ERROR] could not read {prefs_path}: {e}\n")
    sys.exit(1)
keys = doc.get("keys", {})
errors = []

# I3: account_list is a JSON-encoded string (see lib/util/prefs/account_prefs.dart
# `_setAccountListImpl` — stored via `setString(..., jsonEncode(accounts))`),
# decoding to a JSON array with exactly 1 entry whose `toxId` matches the
# current_account_tox_id.
al = keys.get("account_list")
current_tox_id = (keys.get("current_account_tox_id") or {}).get("value") or ""
if not al or al.get("type") != "string":
    observed = al.get("type") if al else "<missing>"
    errors.append(
        f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
        f"whose toxId matches current_account_tox_id; got type={observed!r}"
    )
else:
    raw = al.get("value") or ""
    try:
        entries = json.loads(raw)
    except Exception as e:
        entries = None
        errors.append(
            f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
            f"whose toxId matches current_account_tox_id; got value not parseable as JSON ({e}): {raw!r}"
        )
    if entries is not None:
        if not isinstance(entries, list):
            errors.append(
                f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
                f"whose toxId matches current_account_tox_id; got non-array JSON: {entries!r}"
            )
        elif len(entries) != 1:
            errors.append(
                f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
                f"whose toxId matches current_account_tox_id; got {len(entries)} entries: {entries!r}"
            )
        else:
            entry = entries[0]
            if not isinstance(entry, dict):
                errors.append(
                    f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
                    f"whose toxId matches current_account_tox_id; got non-object entry: {entry!r}"
                )
            else:
                entry_tox_id = entry.get("toxId") or ""
                if not current_tox_id:
                    errors.append(
                        f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
                        f"whose toxId matches current_account_tox_id; current_account_tox_id is empty"
                    )
                elif entry_tox_id != current_tox_id:
                    errors.append(
                        f"I3: flutter.account_list must be a JSON-encoded string containing exactly 1 entry "
                        f"whose toxId matches current_account_tox_id; got entry.toxId={entry_tox_id!r} != "
                        f"current_account_tox_id={current_tox_id!r}"
                    )

# I4: current_account_tox_id matches prefix.
cat = keys.get("current_account_tox_id")
if not cat or cat.get("type") != "string":
    errors.append("I4: flutter.current_account_tox_id missing or not a string")
else:
    v = cat.get("value") or ""
    if not v.startswith(prefix):
        errors.append(f"I4: flutter.current_account_tox_id={v!r} does not start with prefix {prefix!r}")

# I5: local_friends_<prefix> has exactly 1 entry whose value is the friend's
# 64-char Tox public key (i.e. the first 64 chars of the 76-char Tox address).
# Tox stores friends by pubkey, not the full NoSpam-bearing address — see
# third_party/tim2tox: V2TIMManager friend storage uses tox_friend_get_public_key.
lf_key = f"local_friends_{prefix}"
lf = keys.get(lf_key)
if not lf or lf.get("type") != "string_list":
    errors.append(f"I5: flutter.{lf_key} missing or not a string_list")
else:
    vals = lf.get("value") or []
    if len(vals) != 1:
        errors.append(f"I5: flutter.{lf_key} expected exactly 1 entry (the echo peer), got {len(vals)}: {vals!r}")
    else:
        stored = vals[0]
        if len(stored) != 64 or not peer_id.startswith(stored):
            errors.append(
                f"I5: flutter.{lf_key}[0] (64-char pubkey) must be the first 64 chars of peer_id; "
                f"got stored={stored!r} peer_id={peer_id!r}"
            )

if errors:
    for e in errors:
        sys.stderr.write(f"[regen ERROR] {e}\n")
    sys.exit(1)
print("Prefs invariants OK (I3-I5)")
PY
ok "snapshot invariants validated (I1 profile dir, I2 account_data dir, I3 account_list, I4 current_account_tox_id, I5 local_friends)"

# -------------- Pack -------------------------------------------------------
info "packing tarball -> $CACHE_TARBALL"
TARBALL_TMP="${CACHE_TARBALL}.tmp"
rm -f "$TARBALL_TMP"
( cd "$STAGE_DIR" && tar -cf - disk prefs manifest.json | zstd -q -19 -o "$TARBALL_TMP" )
mv -f "$TARBALL_TMP" "$CACHE_TARBALL"
TARBALL_SIZE_BYTES="$(stat -f '%z' "$CACHE_TARBALL")"
ok "tarball size: ${TARBALL_SIZE_BYTES} bytes"

# -------------- Sibling manifest (atomic) ----------------------------------
SIBLING_TMP="${SIBLING_MANIFEST}.tmp.$$"
cp "$MANIFEST_PATH" "$SIBLING_TMP"
mv -f "$SIBLING_TMP" "$SIBLING_MANIFEST"
ok "sibling manifest updated at $SIBLING_MANIFEST"

# -------------- Stop echo peer --------------------------------------------
"$MCP_DIR/stop_echo_peer.sh" >/dev/null 2>&1 || true
STOP_PEER_ON_EXIT=0  # already stopped

# -------------- Summary ----------------------------------------------------
echo
echo "=================================================================="
ok "regen complete"
echo "  machine_id:        $machine_id"
echo "  peer_id:           ${PEER_ID:0:16}... (76 chars)"
echo "  account prefix:    $PREFIX"
echo "  prefs key count:   $KEY_COUNT"
echo "  tarball:           $CACHE_TARBALL"
echo "  tarball size:      ${TARBALL_SIZE_BYTES} bytes"
echo "  sibling manifest:  $SIBLING_MANIFEST"
echo "=================================================================="
