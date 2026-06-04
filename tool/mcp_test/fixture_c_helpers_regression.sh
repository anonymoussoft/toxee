#!/usr/bin/env bash
# Fixture C helper regression checks.
#
# These tests avoid launching Toxee. They exercise the file-level contracts that
# make the multi-instance harness reusable:
#   1. paired_for_e2e restore copies A/B fixture trees into a caller-provided
#      per-instance support root and writes a machine-readable restore report;
#   2. instance.json writing records the explicitly configured SharedPreferences
#      and TCCF isolation values instead of relying on parent-shell env leakage.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RESTORE_SH="$MCP_DIR/restore_fixture_c_pair.sh"
FIXTURES_DIR="$MCP_DIR/fixtures"
MANIFEST_JSON="$FIXTURES_DIR/paired_for_e2e_manifest.json"
INSTANCE_JSON_WRITER="$MCP_DIR/_write_toxee_instance_json.py"
RUN_NON_MEDIA_SH="$MCP_DIR/run_fixture_c_non_media.sh"
DRIVE_PAIR_DART="$MCP_DIR/drive_fixture_c_pair.dart"

# The paired_for_e2e source trees carry throwaway Tox secret keys and are NOT
# committed, so the restore-copy contract self-skips when they are absent (e.g.
# in CI). Everything else here is fixture-independent and always runs. Set
# TOXEE_FIXTURE_C_REQUIRE_FIXTURES=1 to turn the skip into a hard failure (for a
# future build that does ship or seed the fixtures).
REQUIRE_FIXTURES="${TOXEE_FIXTURE_C_REQUIRE_FIXTURES:-0}"

command -v jq >/dev/null 2>&1 || {
    echo "fixture_c_helpers_regression.sh: jq is required" >&2
    exit 1
}

if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    C_GREEN="$(tput setaf 2)"
    C_RED="$(tput setaf 1)"
    C_YELLOW="$(tput setaf 3)"
    C_DIM="$(tput dim)"
    C_RST="$(tput sgr0)"
else
    C_GREEN=""
    C_RED=""
    C_YELLOW=""
    C_DIM=""
    C_RST=""
fi

PASS_COUNT=0
FAIL_COUNT=0
SKIP_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '%s  PASS  %s%s\n' "${C_GREEN}" "$1" "${C_RST}"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '%s  FAIL  %s%s\n' "${C_RED}" "$1" "${C_RST}"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}

note() {
    printf '%s        %s%s\n' "${C_DIM}" "$1" "${C_RST}"
}

skip() {
    SKIP_COUNT=$((SKIP_COUNT + 1))
    printf '%s  SKIP  %s%s\n' "${C_YELLOW}" "$1" "${C_RST}"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}

assert_file() {
    local path="$1"
    local label="$2"
    if [[ ! -f "$path" ]]; then
        fail "$label" "missing file: $path"
        return 1
    fi
    return 0
}

assert_jq() {
    local file="$1"
    local expr="$2"
    local label="$3"
    if ! jq -e "$expr" "$file" >/dev/null; then
        fail "$label" "jq assertion failed: $expr in $file"
        return 1
    fi
    return 0
}

TMP_ROOT="$(mktemp -d -t fixture_c_helpers.XXXXXX)"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "Fixture C helper regressions"
echo "  restore:  $RESTORE_SH"
echo "  manifest: $MANIFEST_JSON"
echo "  writer:   $INSTANCE_JSON_WRITER"
echo "  runner:   $RUN_NON_MEDIA_SH"
echo "  driver:   $DRIVE_PAIR_DART"
echo

# The paired fixture MANIFEST is committed harness source and is MANDATORY: a
# missing/renamed manifest is a real regression (failed in preflight below), not
# a skip. The A/B source TREES it points at carry throwaway Tox secret keys and
# are NOT committed, so ONLY their absence (with the manifest present) downgrades
# the restore-copy contract to a skip. Everything else here is fixture-
# independent and always runs.
FIXTURES_PRESENT=1
FIXTURE_SKIP_REASON=""
if [[ -f "$MANIFEST_JSON" ]]; then
    _A_FIXTURE_DIR="$(jq -r '.instances.A.fixture_dir // empty' "$MANIFEST_JSON")"
    _B_FIXTURE_DIR="$(jq -r '.instances.B.fixture_dir // empty' "$MANIFEST_JSON")"
    if [[ -z "$_A_FIXTURE_DIR" || -z "$_B_FIXTURE_DIR" \
        || ! -d "$FIXTURES_DIR/$_A_FIXTURE_DIR" \
        || ! -d "$FIXTURES_DIR/$_B_FIXTURE_DIR" ]]; then
        FIXTURES_PRESENT=0
        FIXTURE_SKIP_REASON="paired_for_e2e A/B source trees not present under $FIXTURES_DIR (secret-bearing, uncommitted)"
    fi
fi
# A MISSING manifest is intentionally NOT downgraded to a skip here — it is
# mandatory source and is failed in the preflight block below.
if [[ "$FIXTURES_PRESENT" == "0" && "$REQUIRE_FIXTURES" != "1" ]]; then
    note "paired_for_e2e A/B trees absent — restore-copy checks will SKIP"
    note "($FIXTURE_SKIP_REASON)"
fi

if [[ ! -x "$RESTORE_SH" ]]; then
    fail "preflight restore script executable" "missing or not executable: $RESTORE_SH"
else
    pass "preflight restore script executable"
fi
if [[ -f "$MANIFEST_JSON" ]]; then
    pass "preflight paired fixture manifest"
else
    fail "preflight paired fixture manifest" \
        "missing committed harness source: $MANIFEST_JSON"
fi
if [[ ! -f "$INSTANCE_JSON_WRITER" ]]; then
    fail "preflight instance json writer" "missing: $INSTANCE_JSON_WRITER"
else
    pass "preflight instance json writer"
fi
if [[ ! -x "$RUN_NON_MEDIA_SH" ]]; then
    fail "preflight non-media runner executable" "missing or not executable: $RUN_NON_MEDIA_SH"
else
    pass "preflight non-media runner executable"
fi
if [[ ! -f "$DRIVE_PAIR_DART" ]]; then
    fail "preflight pair driver file" "missing: $DRIVE_PAIR_DART"
else
    pass "preflight pair driver file"
fi
if (( FAIL_COUNT > 0 )); then
    exit 1
fi

# 1. Restore paired fixture into a disposable support root. Needs the
#    uncommitted paired_for_e2e source trees; self-skips when they are absent.
if [[ "$FIXTURES_PRESENT" != "1" ]]; then
    if [[ "$REQUIRE_FIXTURES" == "1" ]]; then
        fail "restore paired fixture contract" \
            "$FIXTURE_SKIP_REASON (TOXEE_FIXTURE_C_REQUIRE_FIXTURES=1)"
    else
        skip "restore report written" "$FIXTURE_SKIP_REASON"
        skip "A profile restored"
        skip "B profile restored"
        skip "A chat history restored"
        skip "B chat history restored"
        skip "restore report marks both instances restored"
    fi
else
    RESTORE_ROOT="$TMP_ROOT/restore_root"
    RESTORE_OUT="$TMP_ROOT/restore.out"
    TOXEE_FIXTURE_C_RESTORE_ROOT="$RESTORE_ROOT" "$RESTORE_SH" >"$RESTORE_OUT"
    RESTORE_REPORT="$RESTORE_ROOT/fixture_c_pair_restore.json"

    if assert_file "$RESTORE_REPORT" "restore report written"; then
        pass "restore report written"
    fi

    A_PREFIX="$(jq -r '.instances.A.tox_id[0:16]' "$MANIFEST_JSON")"
    B_PREFIX="$(jq -r '.instances.B.tox_id[0:16]' "$MANIFEST_JSON")"
    A_ID="$(jq -r '.instances.A.tox_id' "$MANIFEST_JSON")"
    B_ID="$(jq -r '.instances.B.tox_id' "$MANIFEST_JSON")"

    if assert_file "$RESTORE_ROOT/A/profiles/p_${A_PREFIX}/tox_profile.tox" \
        "A profile restored"; then
        pass "A profile restored"
    fi
    if assert_file "$RESTORE_ROOT/B/profiles/p_${B_PREFIX}/tox_profile.tox" \
        "B profile restored"; then
        pass "B profile restored"
    fi
    if assert_file "$RESTORE_ROOT/A/account_data/${A_PREFIX}/chat_history/${B_ID}.json" \
        "A chat history restored"; then
        pass "A chat history restored"
    fi
    if assert_file "$RESTORE_ROOT/B/account_data/${B_PREFIX}/chat_history/${A_ID}.json" \
        "B chat history restored"; then
        pass "B chat history restored"
    fi

    if assert_jq "$RESTORE_REPORT" \
        '.format_version == 1 and .instances.A.restored == true and .instances.B.restored == true' \
        "restore report marks both instances restored"; then
        pass "restore report marks both instances restored"
    fi
fi

# 2. Write instance.json with explicit isolation values.
JSON_DIR="$TMP_ROOT/json"
mkdir -p "$JSON_DIR/build" "$JSON_DIR/home" "$JSON_DIR/support"
touch "$JSON_DIR/support/flutter_client.log"

python3 "$INSTANCE_JSON_WRITER" \
    --json-file "$JSON_DIR/instance.json" \
    --instance-name A \
    --pid 12345 \
    --start-time "Mon Jun  1 12:00:00 2026" \
    --cmdline "/tmp/Toxee" \
    --home-override-dir "$JSON_DIR/home" \
    --app-support-override-dir "$JSON_DIR/support" \
    --shared-prefs-prefix "toxee_a." \
    --tccf-global-subdir "multi_instance/A/tccfglobal" \
    --build-dir "$JSON_DIR/build" \
    --stdio-log "$JSON_DIR/build/toxee_stdio.log" \
    --vm-uri-file "$JSON_DIR/build/vm_service_uri.txt" \
    --vm-uri "http://127.0.0.1:50000" \
    --ws-uri "ws://127.0.0.1:50000/ws" \
    --app-support-log "$JSON_DIR/support/flutter_client.log" \
    --default-support-log "$JSON_DIR/default/flutter_client.log"

if assert_jq "$JSON_DIR/instance.json" \
    '.shared_prefs_prefix == "toxee_a." and .tccf_global_subdir == "multi_instance/A/tccfglobal"' \
    "instance json records explicit isolation values"; then
    pass "instance json records explicit isolation values"
fi
if assert_jq "$JSON_DIR/instance.json" \
    '.app_support_log_exists == true and .default_support_log_exists == false' \
    "instance json records support-log existence"; then
    pass "instance json records support-log existence"
fi

# 3. The non-media wrapper must expose both the fresh-handshake and restored
# paired-fixture modes without launching Toxee.
HELP_OUT="$TMP_ROOT/run_fixture_c_non_media.help"
"$RUN_NON_MEDIA_SH" --help >"$HELP_OUT"
if grep -q 'fresh' "$HELP_OUT" && grep -q 'paired_for_e2e' "$HELP_OUT"; then
    pass "non-media runner documents fresh and paired modes"
else
    fail "non-media runner documents fresh and paired modes" \
        "expected --help to mention fresh and paired_for_e2e"
fi

set +e
(cd "$REPO_ROOT" && dart run tool/mcp_test/drive_fixture_c_pair.dart) \
    >"$TMP_ROOT/drive_fixture_c_no_args.out" 2>&1
DRIVE_USAGE_CODE=$?
set -e
if [[ "$DRIVE_USAGE_CODE" -eq 64 ]]; then
    pass "pair driver propagates usage exit code"
else
    fail "pair driver propagates usage exit code" \
        "expected 64 for no args, got $DRIVE_USAGE_CODE"
fi

echo
if (( FAIL_COUNT == 0 )); then
    printf '%sFixture C helper regressions: PASS (%d checks, %d skipped)%s\n' \
        "$C_GREEN" "$PASS_COUNT" "$SKIP_COUNT" "$C_RST"
else
    printf '%sFixture C helper regressions: FAIL (%d failed, %d passed, %d skipped)%s\n' \
        "$C_RED" "$FAIL_COUNT" "$PASS_COUNT" "$SKIP_COUNT" "$C_RST"
fi
exit "$FAIL_COUNT"
