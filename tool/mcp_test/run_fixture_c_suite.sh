#!/usr/bin/env bash
# Class: suite-runner
# Thin compatibility delegate for the unified Fixture C / real-UI runner.
#
# Legacy semantics preserved here:
#   - default to --tier=non-media when no explicit --tier=* is supplied
#   - forward --include-destructive unchanged
#
# Everything else is passed through directly to
# tool/mcp_test/fixture_c_unified_runner.dart so newer planning flags such as
# --dry-run / --list / --plan-json / --validate-only work without teaching this
# wrapper about them one-by-one.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNNER_REL="tool/mcp_test/fixture_c_unified_runner.dart"
RUNNER_PATH="$REPO_ROOT/$RUNNER_REL"

usage() {
    cat <<EOF
usage: run_fixture_c_suite.sh [runner flags]

Thin delegate to $RUNNER_REL.

Compatibility behavior:
  --tier=non-media        default when no explicit --tier=* is supplied
  --include-destructive   forwarded unchanged

Common forwarded runner flags:
  --dry-run               print the planned commands only
  --list                  list resolved manifest entries
  --plan-json             emit grouped execution plan JSON
  --validate-only         validate manifest/planning inputs without running
  --id=...                select specific manifest entries
  --class=...             filter by manifest class (for example 2proc-ui)
  --real-ui-scenario=...  narrow real-UI scenario expansion
  -h, --help              this help
EOF
}

runner_args=()
have_tier=0

for arg in "$@"; do
    case "$arg" in
        -h|--help|help)
            usage
            exit 0
            ;;
        --tier=*)
            have_tier=1
            ;;
    esac
    runner_args+=("$arg")
done

if [[ ! -f "$RUNNER_PATH" ]]; then
    echo "run_fixture_c_suite.sh: unified runner not found: $RUNNER_PATH" >&2
    exit 70
fi

[[ "$have_tier" -eq 1 ]] || runner_args=(--tier=non-media ${runner_args[@]:+"${runner_args[@]}"})

cd "$REPO_ROOT"
exec dart run "$RUNNER_REL" ${runner_args[@]:+"${runner_args[@]}"}
