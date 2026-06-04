#!/usr/bin/env bash
# Stop the A/B pair previously launched by launch_fixture_c_pair.sh.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"

"$MCP_DIR/stop_toxee_instance.sh" B || true
"$MCP_DIR/stop_toxee_instance.sh" A || true

orphans="$(pgrep -fl 'Debug/Toxee.app' 2>/dev/null || true)"
if [[ -n "$orphans" ]]; then
    echo "WARN: pgrep still sees Toxee processes after pair stop:" >&2
    printf '%s\n' "$orphans" >&2
else
    echo "OK: no Debug/Toxee.app processes remain"
fi
