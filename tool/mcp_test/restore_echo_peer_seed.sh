#!/usr/bin/env bash
# Echo peer fixture — Phase 4 restore-from-snapshot.
#
# Wipes current Toxee state and replays a previously-captured seed tarball
# from tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst.
# If no cache exists for this host, regen_echo_peer_seed.sh is invoked first
# (unless RESTORE_NO_REGEN is set).
#
# macOS ONLY in v2.3. The script reads manifest.supported_platforms inside
# the tarball before doing anything destructive, so a Linux/Windows host that
# inherits a macOS-only cache bails out without corrupting state.
#
# Env overrides:
#   RESTORE_NO_REGEN      if set, refuse to call regen_echo_peer_seed.sh
#                         when the cache is missing (CI uses this; the cache
#                         must be staged out-of-band).
#   RESTORE_VERIFY        if set, sha256 the restored disk subtree and print
#                         it for cross-script integrity checks.
#
# Reference: /tmp/codex_round7/echo_peer_v2.3.md §4 "restore_echo_peer_seed.sh
# — replay snapshot".
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
FIXTURES_DIR="$MCP_DIR/fixtures"
CACHE_DIR="$FIXTURES_DIR/.cache"

TOXEE_SUPPORT_DIR="$HOME/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app"
TOXEE_PROFILES_DIR="$TOXEE_SUPPORT_DIR/profiles"
TOXEE_ACCOUNT_DATA_DIR="$TOXEE_SUPPORT_DIR/account_data"
TOXEE_DOMAIN="com.toxee.app"
KNOWN_FORMAT_VERSION=1
THIS_PLATFORM="macos"

# -------------- TTY colors -------------------------------------------------
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_GREEN="$(tput setaf 2)"; C_RED="$(tput setaf 1)"; C_YELLOW="$(tput setaf 3)"
    C_DIM="$(tput dim)"; C_RST="$(tput sgr0)"
else
    C_GREEN=""; C_RED=""; C_YELLOW=""; C_DIM=""; C_RST=""
fi
info() { printf '%s[restore]%s %s\n' "${C_DIM}" "${C_RST}" "$*"; }
warn() { printf '%s[restore WARN]%s %s\n' "${C_YELLOW}" "${C_RST}" "$*" >&2; }
die()  { printf '%s[restore ERROR]%s %s\n' "${C_RED}"  "${C_RST}" "$*" >&2; exit 1; }
ok()   { printf '%s[restore OK]%s %s\n' "${C_GREEN}" "${C_RST}" "$*"; }

# -------------- Pre-flight -------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "restore is macOS-only in v2.3 (got $(uname -s))"
command -v zstd >/dev/null 2>&1 || die "zstd missing; install with: brew install zstd"
command -v tar  >/dev/null 2>&1 || die "tar missing"
command -v jq   >/dev/null 2>&1 || die "jq missing; install with: brew install jq"
command -v defaults >/dev/null 2>&1 || die "defaults missing"

# jq 1.7+ provides --raw-output0 (NUL terminator) which we use for string_list.
jq_ver="$(jq --version 2>/dev/null | sed -E 's/^jq-?//; s/-.*//')"
if [[ -n "$jq_ver" ]]; then
    jq_major="${jq_ver%%.*}"
    jq_rest="${jq_ver#*.}"
    jq_minor="${jq_rest%%.*}"
    if [[ "$jq_major" -lt 1 ]] || { [[ "$jq_major" -eq 1 ]] && [[ "$jq_minor" -lt 7 ]]; }; then
        die "jq >= 1.7 required for --raw-output0 (have $jq_ver)"
    fi
fi

machine_id="$(ioreg -d2 -c IOPlatformExpertDevice 2>/dev/null \
    | awk '/IOPlatformUUID/{print $3}' | tr -d '"' | head -n1 || true)"
if [[ -z "$machine_id" ]]; then
    machine_id="$(hostname -s 2>/dev/null || echo unknown)"
fi
machine_id="$(printf '%s' "$machine_id" | tr -c 'A-Za-z0-9_-' '_' | head -c 64)"
info "machine_id=$machine_id"

CACHE_TARBALL="$CACHE_DIR/echo_peer_seeded_${machine_id}.tar.zst"

# -------------- Locate or regen --------------------------------------------
if [[ ! -f "$CACHE_TARBALL" ]]; then
    if [[ -n "${RESTORE_NO_REGEN:-}" ]]; then
        die "no cache at $CACHE_TARBALL and RESTORE_NO_REGEN is set"
    fi
    warn "no cache at $CACHE_TARBALL; invoking regen first"
    "$MCP_DIR/regen_echo_peer_seed.sh"
    [[ -f "$CACHE_TARBALL" ]] || die "regen ran but did not produce $CACHE_TARBALL"
fi
ok "cache: $CACHE_TARBALL"

# -------------- Stage extract ----------------------------------------------
STAGE_DIR="$(mktemp -d -t echo_peer_restore)"
cleanup() {
    if [[ -n "${STAGE_DIR:-}" && -d "$STAGE_DIR" ]]; then
        rm -rf "$STAGE_DIR"
    fi
}
trap cleanup EXIT

info "extracting tarball -> $STAGE_DIR"
zstd -q -d -c "$CACHE_TARBALL" | tar -xf - -C "$STAGE_DIR"

MANIFEST_PATH="$STAGE_DIR/manifest.json"
[[ -f "$MANIFEST_PATH" ]] || die "tarball is missing manifest.json"

# -------------- Manifest gate (before any destructive op) -----------------
fmt_ver="$(jq -r '.format_version // empty' "$MANIFEST_PATH")"
[[ "$fmt_ver" == "$KNOWN_FORMAT_VERSION" ]] \
    || die "manifest.format_version=$fmt_ver; this restore tool understands $KNOWN_FORMAT_VERSION"

if ! jq -e --arg p "$THIS_PLATFORM" '.supported_platforms | index($p)' "$MANIFEST_PATH" >/dev/null; then
    supported="$(jq -r '.supported_platforms | join(",")' "$MANIFEST_PATH")"
    die "manifest does not list '$THIS_PLATFORM' in supported_platforms (got: $supported)"
fi
ok "manifest gate passed (format_version=$fmt_ver, supports $THIS_PLATFORM)"

MANIFEST_PEER_ID="$(jq -r '.peer_id // empty' "$MANIFEST_PATH")"
MANIFEST_PREFIX="$(jq -r '.prefix // empty' "$MANIFEST_PATH")"
MANIFEST_KEY_COUNT="$(jq -r '.key_count_expected // 0' "$MANIFEST_PATH")"

# -------------- Wipe current state -----------------------------------------
info "wiping current toxee state"
pkill -f "Debug/Toxee.app" 2>/dev/null || true
sleep 1
if [[ -d "$TOXEE_PROFILES_DIR" ]]; then
    find "$TOXEE_PROFILES_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
fi
if [[ -d "$TOXEE_ACCOUNT_DATA_DIR" ]]; then
    find "$TOXEE_ACCOUNT_DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf {} + || true
fi
defaults delete "$TOXEE_DOMAIN" 2>/dev/null || true
killall cfprefsd 2>/dev/null || true

# -------------- Restore disk -----------------------------------------------
mkdir -p "$TOXEE_PROFILES_DIR" "$TOXEE_ACCOUNT_DATA_DIR"
if [[ -d "$STAGE_DIR/disk/profiles" ]] && \
   [ "$(find "$STAGE_DIR/disk/profiles" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    cp -a "$STAGE_DIR/disk/profiles/." "$TOXEE_PROFILES_DIR/"
fi
if [[ -d "$STAGE_DIR/disk/account_data" ]] && \
   [ "$(find "$STAGE_DIR/disk/account_data" -mindepth 1 -maxdepth 1 | wc -l)" -gt 0 ]; then
    cp -a "$STAGE_DIR/disk/account_data/." "$TOXEE_ACCOUNT_DATA_DIR/"
fi
ok "disk restored"

# -------------- Restore Prefs ----------------------------------------------
PREFS_JSON="$STAGE_DIR/prefs/prefs_dump.json"
[[ -f "$PREFS_JSON" ]] || die "tarball is missing prefs/prefs_dump.json"

prefs_format_version="$(jq -r '.format_version // 0' "$PREFS_JSON")"
[[ "$prefs_format_version" == "$KNOWN_FORMAT_VERSION" ]] \
    || die "prefs_dump.format_version=$prefs_format_version; expected $KNOWN_FORMAT_VERSION"
KEY_PREFIX="$(jq -r '.key_prefix // "flutter."' "$PREFS_JSON")"

written=0
while IFS= read -r short_key; do
    [[ -z "$short_key" ]] && continue
    type_tag="$(jq -r --arg k "$short_key" '.keys[$k].type' "$PREFS_JSON")"
    full_key="${KEY_PREFIX}${short_key}"
    case "$type_tag" in
        string)
            val="$(jq -r --arg k "$short_key" '.keys[$k].value' "$PREFS_JSON")"
            defaults write "$TOXEE_DOMAIN" "$full_key" -string "$val"
            ;;
        bool)
            val="$(jq -r --arg k "$short_key" '.keys[$k].value' "$PREFS_JSON")"
            if [[ "$val" == "true" ]]; then
                defaults write "$TOXEE_DOMAIN" "$full_key" -bool true
            else
                defaults write "$TOXEE_DOMAIN" "$full_key" -bool false
            fi
            ;;
        int)
            val="$(jq -r --arg k "$short_key" '.keys[$k].value' "$PREFS_JSON")"
            defaults write "$TOXEE_DOMAIN" "$full_key" -int "$val"
            ;;
        double)
            val="$(jq -r --arg k "$short_key" '.keys[$k].value' "$PREFS_JSON")"
            defaults write "$TOXEE_DOMAIN" "$full_key" -float "$val"
            ;;
        string_list)
            # NUL-separated read so embedded whitespace + newlines survive.
            value_items=()
            while IFS= read -r -d '' item; do
                value_items+=("$item")
            done < <(jq --raw-output0 --arg k "$short_key" '.keys[$k].value[]?' "$PREFS_JSON")
            if [[ "${#value_items[@]}" -eq 0 ]]; then
                defaults write "$TOXEE_DOMAIN" "$full_key" -array
            else
                defaults write "$TOXEE_DOMAIN" "$full_key" -array "${value_items[@]}"
            fi
            ;;
        *)
            warn "skipping $short_key: unknown type '$type_tag'"
            continue
            ;;
    esac
    written=$((written + 1))
done < <(jq -r '.keys | keys[]' "$PREFS_JSON")

ok "prefs restored ($written/$MANIFEST_KEY_COUNT keys)"

# -------------- Flush cfprefsd cache --------------------------------------
killall cfprefsd 2>/dev/null || true

# -------------- Optional verify -------------------------------------------
if [[ -n "${RESTORE_VERIFY:-}" ]]; then
    if command -v shasum >/dev/null 2>&1; then
        info "computing restored disk sha256 (RESTORE_VERIFY)"
        ( cd "$TOXEE_SUPPORT_DIR" && \
            find profiles account_data -type f -print0 2>/dev/null \
                | sort -z \
                | xargs -0 shasum -a 256 2>/dev/null \
                | shasum -a 256 ) | awk '{print "  disk sha256: " $1}'
    fi
fi

# -------------- Summary ---------------------------------------------------
echo
echo "=================================================================="
ok "restore complete"
echo "  cache:              $CACHE_TARBALL"
echo "  manifest peer_id:   ${MANIFEST_PEER_ID:0:16}..."
echo "  account prefix:     $MANIFEST_PREFIX"
echo "  prefs keys written: $written (manifest expected $MANIFEST_KEY_COUNT)"
echo "=================================================================="
