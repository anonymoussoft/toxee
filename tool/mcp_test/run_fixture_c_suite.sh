#!/usr/bin/env bash
# Class: suite-runner
# Tiered Fixture C two-process suite runner (plan section 3.4).
#
# Reads tool/mcp_test/fixture_c_manifest.json and runs the run_fixture_c_*.sh
# wrappers in manifest order, filtered by --tier. The manifest is the single
# source of truth for ordering + classification (media / destructive / class);
# this runner adds NO scenario knowledge of its own.
#
#   --tier=non-media   run only media:false entries (DEFAULT)
#   --tier=media       run only media:true  entries (real ToxAV call flows)
#   --tier=all         run every entry, non-media first then media
#   --include-destructive  also run destructive entries (network_drop, kick);
#                          they are SKIPPED by default in every tier
#   -h | --help        usage
#
# The drive_real_ui_pair.dart entry (class 2proc-ui) has NO .sh wrapper and
# needs two manually-launched live instances + an osascript-foreground-able
# session, so it is ALWAYS skipped here with a NOTE — run it by hand per its
# launchNote in the manifest / REAL_UI_TWO_PROCESS.md.
#
# Exit status: 0 only if every RUN entry passed; non-zero if any failed.
# Skipped (wrong tier / destructive-without-flag / 2proc-ui) entries never fail
# the run.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
MANIFEST="$MCP_DIR/fixture_c_manifest.json"

TIER="non-media"
INCLUDE_DESTRUCTIVE=0

usage() {
    cat <<EOF
usage: run_fixture_c_suite.sh [--tier=non-media|media|all] [--include-destructive]

Runs the Fixture C two-process gates listed in fixture_c_manifest.json, in
manifest order, filtered by tier. Destructive gates (network_drop, kick) run
only with --include-destructive. The real-UI driver (drive_real_ui_pair.dart,
class 2proc-ui) is always skipped (no .sh wrapper; run it by hand).

  --tier=non-media        media:false entries only (default)
  --tier=media            media:true entries only
  --tier=all              all entries (non-media first, then media)
  --include-destructive   also run network_drop + kick
  -h, --help              this help
EOF
}

for arg in "$@"; do
    case "$arg" in
        --tier=*)
            TIER="${arg#--tier=}"
            ;;
        --include-destructive)
            INCLUDE_DESTRUCTIVE=1
            ;;
        -h|--help|help)
            usage
            exit 0
            ;;
        *)
            echo "run_fixture_c_suite.sh: unknown argument: $arg" >&2
            usage >&2
            exit 64
            ;;
    esac
done

case "$TIER" in
    non-media|media|all) ;;
    *)
        echo "run_fixture_c_suite.sh: unknown tier: $TIER" >&2
        usage >&2
        exit 64
        ;;
esac

if ! command -v jq >/dev/null 2>&1; then
    echo "run_fixture_c_suite.sh: jq is required to parse $MANIFEST" >&2
    exit 70
fi
if [[ ! -f "$MANIFEST" ]]; then
    echo "run_fixture_c_suite.sh: manifest not found: $MANIFEST" >&2
    exit 70
fi

echo "[suite] tier=$TIER include-destructive=$INCLUDE_DESTRUCTIVE"
echo "[suite] manifest: $MANIFEST"

cd "$REPO_ROOT"

declare -a RESULT_LINES=()
ran=0
passed=0
failed=0
skipped=0

# Iterate manifest entries in order. jq emits one TSV row per entry:
#   script <TAB> class <TAB> media(true|false) <TAB> destructive(true|false) <TAB> scenarios(csv)
# Process substitution (< <(...)) keeps this while-loop in the CURRENT shell so
# the counters/RESULT_LINES survive — and, unlike `mapfile`, it works on the
# bash 3.2 that ships with macOS (no GNU bash 4+ required, matching the other
# fixture wrappers).
while IFS=$'\t' read -r script klass media destructive scenarios; do
    [[ -z "$script" ]] && continue

    # The real-UI driver has no wrapper; always NOTE-skip.
    if [[ "$klass" == "2proc-ui" ]]; then
        echo "[suite] NOTE: skipping $script (class 2proc-ui, no .sh wrapper) — run it by hand (see its launchNote in $MANIFEST)."
        RESULT_LINES+=("$(printf 'SKIP-UI   %-32s %s' "$script" "$scenarios")")
        skipped=$((skipped + 1))
        continue
    fi

    # Recursion guard: run_fixture_c_non_media.sh is now a THIN ALIAS for this
    # runner (--tier=non-media), so running it as a leaf would recurse. It is
    # listed in the manifest only for completeness / the gen_scenario_index
    # cross-check; the suite NOTE-skips it. (Its S61/S62 handshake+delivery
    # contract is still exercised indirectly: every paired wrapper's
    # drive_fixture_c_pair.dart boot+roundtrip preamble covers S62, and
    # run_fixture_c_accept.sh covers the S26 handshake data-path.)
    if [[ "$script" == "run_fixture_c_non_media.sh" || "$script" == "run_fixture_c_suite.sh" ]]; then
        echo "[suite] NOTE: skipping $script (alias/self — avoids recursion)."
        RESULT_LINES+=("$(printf 'SKIP-SELF %-32s %s' "$script" "$scenarios")")
        skipped=$((skipped + 1))
        continue
    fi

    # Tier filter.
    case "$TIER" in
        non-media) [[ "$media" == "false" ]] || { RESULT_LINES+=("$(printf 'SKIP-TIER %-32s %s' "$script" "$scenarios")"); skipped=$((skipped + 1)); continue; } ;;
        media)     [[ "$media" == "true"  ]] || { RESULT_LINES+=("$(printf 'SKIP-TIER %-32s %s' "$script" "$scenarios")"); skipped=$((skipped + 1)); continue; } ;;
        all)       : ;;
    esac

    # Destructive gate.
    if [[ "$destructive" == "true" && "$INCLUDE_DESTRUCTIVE" -ne 1 ]]; then
        echo "[suite] skip $script (destructive; pass --include-destructive to run)"
        RESULT_LINES+=("$(printf 'SKIP-DEST %-32s %s' "$script" "$scenarios")")
        skipped=$((skipped + 1))
        continue
    fi

    local_path="$MCP_DIR/$script"
    if [[ ! -x "$local_path" ]]; then
        echo "[suite] ERROR: $script not found or not executable at $local_path" >&2
        RESULT_LINES+=("$(printf 'FAIL      %-32s %s (missing/not executable)' "$script" "$scenarios")")
        failed=$((failed + 1))
        ran=$((ran + 1))
        continue
    fi

    echo ""
    echo "[suite] ===== RUN $script ($scenarios) ====="
    ran=$((ran + 1))
    # `if` exempts the script from set -e so one failure does not abort the suite.
    if "$local_path"; then
        echo "[suite] PASS $script"
        RESULT_LINES+=("$(printf 'PASS      %-32s %s' "$script" "$scenarios")")
        passed=$((passed + 1))
    else
        rc=$?
        echo "[suite] FAIL $script (exit $rc)"
        RESULT_LINES+=("$(printf 'FAIL      %-32s %s (exit %s)' "$script" "$scenarios" "$rc")")
        failed=$((failed + 1))
    fi
done < <(jq -r '
    .entries[]
    | [ .script,
        (.class // "2proc-l3"),
        (.media | tostring),
        (.destructive | tostring),
        ((.scenarios // []) | join(",")) ]
    | @tsv' "$MANIFEST")

echo ""
echo "========================= Fixture C suite summary ========================="
echo "tier=$TIER include-destructive=$INCLUDE_DESTRUCTIVE"
printf '%-9s %-32s %s\n' "STATUS" "SCRIPT" "SCENARIOS"
echo "---------------------------------------------------------------------------"
# `${arr[@]:+...}` guards the empty-array-under-set-u footgun on bash 3.2.
for line in ${RESULT_LINES[@]:+"${RESULT_LINES[@]}"}; do
    echo "$line"
done
echo "---------------------------------------------------------------------------"
echo "ran=$ran passed=$passed failed=$failed skipped=$skipped"
echo "==========================================================================="

[[ "$failed" -eq 0 ]]
