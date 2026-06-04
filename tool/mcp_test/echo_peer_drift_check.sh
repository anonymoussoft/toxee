#!/usr/bin/env bash
# Compare the toxee-local echo peer source against the upstream tim2tox
# example it was copied from. Run at submodule-bump time as a "do you need to
# backport this upstream change into the local copy?" gate.
#
# Informational only — exits 0 even on drift. The judgment of whether the
# drift matters is left to the human bumping the submodule.
#
# Reference: tool/mcp_test/echo_peer_src/echo_peer.cpp (top-of-file provenance
# comment lists baseline SHA + the toxee-local modifications).
set -euo pipefail

# Locate repo root (this script lives at tool/mcp_test/).
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

LOCAL="$REPO_ROOT/tool/mcp_test/echo_peer_src/echo_peer.cpp"
UPSTREAM="$REPO_ROOT/third_party/tim2tox/example/echo_bot_server.cpp"

if [[ ! -f "$LOCAL" ]]; then
    echo "ERR: missing local copy: $LOCAL" >&2
    exit 2
fi
if [[ ! -f "$UPSTREAM" ]]; then
    echo "ERR: missing upstream baseline: $UPSTREAM" >&2
    echo "     (did you `git submodule update --init --recursive`?)" >&2
    exit 2
fi

# Pin the recorded baseline SHA for visibility. Don't fail on mismatch — that's
# the whole point of this script (the submodule MOVED; we want to see drift).
BASELINE_SHA="$(grep -E '^// Copied from .*@ ' "$LOCAL" | head -n1 | awk '{print $NF}' || true)"
CURRENT_SHA="$(git -C "$REPO_ROOT/third_party/tim2tox" log -1 --format=%H -- example/echo_bot_server.cpp 2>/dev/null || echo unknown)"

echo "echo_peer_drift_check"
echo "  local:           $LOCAL"
echo "  upstream:        $UPSTREAM"
echo "  baseline SHA:    ${BASELINE_SHA:-<not recorded>}"
echo "  current SHA:     $CURRENT_SHA"
echo

if [[ -n "$BASELINE_SHA" && "$BASELINE_SHA" != "$CURRENT_SHA" ]]; then
    echo "NOTE: tim2tox example/echo_bot_server.cpp moved upstream since the local"
    echo "      copy was taken. Diff against current upstream follows."
    echo
fi

# `diff` returns 1 when files differ; that's expected (the local copy has
# toxee-local modifications). Under `set -euo pipefail` the non-zero exit
# in `diff | wc` would kill us, so capture into a tmpfile first and count
# from there.
DIFF_TMP="$(mktemp -t echo_peer_drift_XXXXXX)"
diff -u "$UPSTREAM" "$LOCAL" > "$DIFF_TMP" || true   # 0=same, 1=differ — both ok
DIFF_LINES="$(wc -l < "$DIFF_TMP" | tr -d ' ')"
echo "----- diff -u upstream local -----"
cat "$DIFF_TMP"
echo "----------------------------------"
echo
echo "Drift size: ${DIFF_LINES} lines (unified-diff including hunks)"
rm -f "$DIFF_TMP"
echo
echo "Reminder: drift is expected for the toxee-local modifications"
echo "  - ECHO_PEER_STATE_DIR env support"
echo "  - ECHO_PEER_TOX_ID: dedicated flushed stdout emission"
echo "  - SIGTERM/SIGINT clean teardown"
echo "If upstream introduced NEW behaviour outside those areas, evaluate"
echo "whether to backport it into tool/mcp_test/echo_peer_src/echo_peer.cpp"
echo "and bump the baseline SHA in the provenance comment."
