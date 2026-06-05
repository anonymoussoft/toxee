#!/usr/bin/env bash
# Hermetic regressions for the unified Fixture C / real-UI runner.
#
# These checks never launch Toxee. They validate manifest parsing, filtering,
# grouping, and dry-run command planning before the live two-process runner is
# allowed to mutate local app state.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MCP_DIR="$REPO_ROOT/tool/mcp_test"
RUNNER="$MCP_DIR/fixture_c_unified_runner.dart"

command -v jq >/dev/null 2>&1 || {
    echo "fixture_c_unified_runner_regression.sh: jq is required" >&2
    exit 1
}

PASS_COUNT=0
FAIL_COUNT=0
TMP_ROOT="$(mktemp -d -t fixture_c_unified_runner.XXXXXX)"
cleanup() {
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    printf '  PASS  %s\n' "$1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    printf '  FAIL  %s\n' "$1"
    if [[ -n "${2:-}" ]]; then
        printf '        %s\n' "$2"
    fi
}

run_runner() {
    (cd "$REPO_ROOT" && dart run tool/mcp_test/fixture_c_unified_runner.dart "$@")
}

run_suite() {
    (cd "$REPO_ROOT" && bash tool/mcp_test/run_fixture_c_suite.sh "$@")
}

run_non_media_alias() {
    (cd "$REPO_ROOT" && bash tool/mcp_test/run_fixture_c_non_media.sh "$@")
}

echo "Unified Fixture C runner regressions"
echo "  runner: $RUNNER"
echo

LIST_OUT="$TMP_ROOT/list.out"
if run_runner --list >"$LIST_OUT" 2>"$TMP_ROOT/list.err"; then
    if grep -q 'drive_real_ui_pair.dart' "$LIST_OUT" \
        && grep -q 'run_fixture_c_accept.sh' "$LIST_OUT"; then
        pass "--list includes real-UI and Fixture C entries"
    else
        fail "--list includes real-UI and Fixture C entries" \
            "expected drive_real_ui_pair.dart and run_fixture_c_accept.sh in --list output"
    fi
else
    fail "--list exits 0" "$(cat "$TMP_ROOT/list.err" "$LIST_OUT" 2>/dev/null)"
fi

CAMPAIGN_LIST_OUT="$TMP_ROOT/real_ui_campaigns.out"
if run_runner --list-real-ui-campaigns >"$CAMPAIGN_LIST_OUT" \
    2>"$TMP_ROOT/campaigns.err"; then
    CAMPAIGN_COUNT="$(awk -F'[()]' 'NR==1 {print $2}' "$CAMPAIGN_LIST_OUT")"
    CAMPAIGN_ENTRY_COUNT="$(grep -c '^[a-z0-9][a-z0-9-]*:' "$CAMPAIGN_LIST_OUT" || true)"
    if [[ -n "$CAMPAIGN_COUNT" && "$CAMPAIGN_COUNT" -ge 30 ]]; then
        pass "--list-real-ui-campaigns exposes at least 30 reusable campaigns"
    else
        fail "--list-real-ui-campaigns exposes at least 30 reusable campaigns" \
            "expected >=30 campaigns, got ${CAMPAIGN_COUNT:-missing}"
    fi
    if [[ -n "$CAMPAIGN_COUNT" && "$CAMPAIGN_COUNT" == "$CAMPAIGN_ENTRY_COUNT" ]]; then
        pass "campaign catalog header count matches the discoverability listing"
    else
        fail "campaign catalog header count matches the discoverability listing" \
            "header=${CAMPAIGN_COUNT:-missing} entries=$CAMPAIGN_ENTRY_COUNT"
    fi
    if grep -q '^accepted-friend-inline-full:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^no-friend-inline-call:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^inline-call-then-decline:' "$CAMPAIGN_LIST_OUT" \
        && grep -q '^all-expanded:' "$CAMPAIGN_LIST_OUT"; then
        pass "campaign catalog includes representative bucket samples"
    else
        fail "campaign catalog includes representative bucket samples"
    fi
else
    fail "--list-real-ui-campaigns exits 0" \
        "$(cat "$TMP_ROOT/campaigns.err" "$CAMPAIGN_LIST_OUT" 2>/dev/null)"
fi

PLAN_JSON="$TMP_ROOT/non_media_plan.json"
if run_runner --plan-json --tier=non-media >"$PLAN_JSON" 2>"$TMP_ROOT/plan.err"; then
    if jq -e '.groups | length > 0' "$PLAN_JSON" >/dev/null; then
        pass "--plan-json emits groups"
    else
        fail "--plan-json emits groups" "no groups emitted"
    fi
    if jq -e '[.groups[].entries[].script] | index("drive_real_ui_pair.dart")' \
        "$PLAN_JSON" >/dev/null; then
        pass "planning includes 2proc-ui instead of skipping it"
    else
        fail "planning includes 2proc-ui instead of skipping it"
    fi
    if jq -e '[.groups[].entries[] | select(.destructive == true)] | length == 0' \
        "$PLAN_JSON" >/dev/null; then
        pass "destructive entries excluded by default"
    else
        fail "destructive entries excluded by default"
    fi
    if jq -e '.groups[0].mode == "paired-reuse"' "$PLAN_JSON" >/dev/null; then
        pass "paired reusable group is planned first"
    else
        fail "paired reusable group is planned first" \
            "first group should amortize paired_for_e2e launch"
    fi
    if jq -e '
        [.groups[].entries[] | select(.script == "run_fixture_c_accept.sh")][0]
        | .base == "fresh" and .driver == "drive_fixture_c_accept.dart"
    ' "$PLAN_JSON" >/dev/null; then
        pass "plan-json exposes explicit driver/base metadata"
    else
        fail "plan-json exposes explicit driver/base metadata"
    fi
else
    fail "--plan-json exits 0" "$(cat "$TMP_ROOT/plan.err" "$PLAN_JSON" 2>/dev/null)"
fi

DESTRUCTIVE_PLAN="$TMP_ROOT/destructive_plan.json"
if run_runner --plan-json --tier=all --include-destructive >"$DESTRUCTIVE_PLAN" \
    2>"$TMP_ROOT/destructive.err"; then
    if jq -e '[.groups[].entries[] | select(.destructive == true)] | length > 0' \
        "$DESTRUCTIVE_PLAN" >/dev/null; then
        pass "--include-destructive includes destructive entries"
    else
        fail "--include-destructive includes destructive entries"
    fi
else
    fail "--include-destructive plan exits 0" \
        "$(cat "$TMP_ROOT/destructive.err" "$DESTRUCTIVE_PLAN" 2>/dev/null)"
fi

DRY_OUT="$TMP_ROOT/dry_run.out"
if run_runner --dry-run --tier=non-media >"$DRY_OUT" 2>"$TMP_ROOT/dry.err"; then
    if grep -q 'launch_fixture_c_pair.sh' "$DRY_OUT" \
        && grep -q 'drive_fixture_c_pair.dart' "$DRY_OUT"; then
        pass "--dry-run prints launch and driver commands"
    else
        fail "--dry-run prints launch and driver commands" \
            "expected launch_fixture_c_pair.sh and drive_fixture_c_pair.dart"
    fi
else
    fail "--dry-run exits 0" "$(cat "$TMP_ROOT/dry.err" "$DRY_OUT" 2>/dev/null)"
fi

ACCEPT_PLAN="$TMP_ROOT/accept_plan.json"
if run_runner --plan-json --id=run_fixture_c_accept.sh >"$ACCEPT_PLAN" \
    2>"$TMP_ROOT/accept.err"; then
    if jq -e '(.groups | length) == 1 and .groups[0].mode == "fresh-isolated"' \
        "$ACCEPT_PLAN" >/dev/null; then
        pass "fresh friend-request gates stay isolated"
    else
        fail "fresh friend-request gates stay isolated" \
            "run_fixture_c_accept.sh should not be batched into paired reuse"
    fi
else
    fail "fresh accept plan exits 0" "$(cat "$TMP_ROOT/accept.err" "$ACCEPT_PLAN" 2>/dev/null)"
fi

ALL_DRY="$TMP_ROOT/all_dry.out"
if run_runner --dry-run --tier=all >"$ALL_DRY" 2>"$TMP_ROOT/all_dry.err"; then
    if grep -q 'drive_fixture_c_file.dart "\$A_WS" "\$B_WS" --fixture-manifest .* --image' \
        "$ALL_DRY"; then
        pass "image gate reuses file driver with --image"
    else
        fail "image gate reuses file driver with --image"
    fi
else
    fail "all-tier dry-run exits 0" "$(cat "$TMP_ROOT/all_dry.err" "$ALL_DRY" 2>/dev/null)"
fi

REAL_UI_DRY="$TMP_ROOT/real_ui_dry.out"
if run_runner --dry-run --class=2proc-ui >"$REAL_UI_DRY" 2>"$TMP_ROOT/real_ui.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_DRY" \
        && grep -q 'drive_real_ui_pair.dart decline ' "$REAL_UI_DRY"; then
        pass "real-UI dry-run expands scenario sequence"
    else
        fail "real-UI dry-run expands scenario sequence" \
            "expected handshake/message/handshake_detail/decline commands"
    fi
    LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_DRY" || true)"
    if [[ "$LAUNCH_COUNT" -eq 1 ]]; then
        pass "real-UI default batch reuses a single launch across all codified scenarios"
    else
        fail "real-UI default batch reuses a single launch across all codified scenarios" \
            "expected 1 launch for the 4-scenario batch, but saw $LAUNCH_COUNT"
    fi
    RESET_COUNT="$(grep -c 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" || true)"
    if [[ "$RESET_COUNT" -eq 2 ]]; then
        pass "real-UI default batch inserts friendship resets between incompatible states"
    else
        fail "real-UI default batch inserts friendship resets between incompatible states" \
            "expected 2 reset_friendship steps, but saw $RESET_COUNT"
    fi
    HANDSHAKE_LINE="$(grep -n 'drive_real_ui_pair.dart handshake ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    RESET1_LINE="$(grep -n 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    RESET2_LINE="$(grep -n 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_DRY" | tail -n1 | cut -d: -f1)"
    DECLINE_LINE="$(grep -n 'drive_real_ui_pair.dart decline ' "$REAL_UI_DRY" | head -n1 | cut -d: -f1)"
    if [[ -n "$HANDSHAKE_LINE" && -n "$MESSAGE_LINE" && -n "$RESET1_LINE" \
        && -n "$DETAIL_LINE" && -n "$RESET2_LINE" && -n "$DECLINE_LINE" \
        && "$HANDSHAKE_LINE" -lt "$MESSAGE_LINE" \
        && "$MESSAGE_LINE" -lt "$RESET1_LINE" \
        && "$RESET1_LINE" -lt "$DETAIL_LINE" \
        && "$DETAIL_LINE" -lt "$RESET2_LINE" \
        && "$RESET2_LINE" -lt "$DECLINE_LINE" ]]; then
        pass "real-UI default batch orders handshake -> message -> reset -> detail -> reset -> decline"
    else
        fail "real-UI default batch orders handshake -> message -> reset -> detail -> reset -> decline"
    fi
else
    fail "real-UI dry-run exits 0" "$(cat "$TMP_ROOT/real_ui.err" "$REAL_UI_DRY" 2>/dev/null)"
fi

REAL_UI_PLAN="$TMP_ROOT/real_ui_plan.json"
if run_runner --plan-json --class=2proc-ui >"$REAL_UI_PLAN" \
    2>"$TMP_ROOT/real_ui_plan.err"; then
    if jq -e '(.groups | length) == 1 and .groups[0].mode == "real-ui"' \
        "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json stays in one dedicated group"
    else
        fail "real-UI plan-json stays in one dedicated group" \
            "expected a single real-ui group"
    fi
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == ["handshake", "message", "handshake_detail", "decline"]
    ' "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json records the default reusable scenario batch"
    else
        fail "real-UI plan-json records the default reusable scenario batch"
    fi
    if jq -e '
        [.groups[0].commands[] | select(contains("reset_friendship"))]
        | length == 2
    ' "$REAL_UI_PLAN" >/dev/null; then
        pass "real-UI plan-json exposes friendship-reset maintenance steps"
    else
        fail "real-UI plan-json exposes friendship-reset maintenance steps" \
            "expected 2 reset_friendship commands in plan-json"
    fi
else
    fail "real-UI plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_plan.err" "$REAL_UI_PLAN" 2>/dev/null)"
fi

REAL_UI_ORDERED_DRY="$TMP_ROOT/real_ui_ordered_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=handshake_detail,message \
    >"$REAL_UI_ORDERED_DRY" 2>"$TMP_ROOT/real_ui_ordered.err"; then
    ORDERED_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_ORDERED_DRY" || true)"
    ORDERED_DETAIL_LINE="$(grep -n 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_ORDERED_DRY" | head -n1 | cut -d: -f1)"
    ORDERED_MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_ORDERED_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$ORDERED_LAUNCH_COUNT" -eq 1 && -n "$ORDERED_DETAIL_LINE" && -n "$ORDERED_MESSAGE_LINE" \
        && "$ORDERED_DETAIL_LINE" -lt "$ORDERED_MESSAGE_LINE" ]]; then
        pass "ordered real-UI selection stays on one launch"
    else
        fail "ordered real-UI selection stays on one launch" \
            "expected a single launch with detail before message, but saw $ORDERED_LAUNCH_COUNT launches"
    fi
else
    fail "ordered real-UI dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_ordered.err" "$REAL_UI_ORDERED_DRY" 2>/dev/null)"
fi

REAL_UI_CAMPAIGN_DRY="$TMP_ROOT/real_ui_campaign_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-detail \
    >"$REAL_UI_CAMPAIGN_DRY" 2>"$TMP_ROOT/real_ui_campaign.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake_detail ' "$REAL_UI_CAMPAIGN_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_CAMPAIGN_DRY" \
        && ! grep -q 'drive_real_ui_pair.dart decline ' "$REAL_UI_CAMPAIGN_DRY"; then
        pass "--real-ui-campaign expands the named merged batch"
    else
        fail "--real-ui-campaign expands the named merged batch"
    fi
else
    fail "real-UI campaign dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_campaign.err" "$REAL_UI_CAMPAIGN_DRY" 2>/dev/null)"
fi

REAL_UI_INLINE_PLAN="$TMP_ROOT/real_ui_inline_plan.json"
if run_runner --plan-json --class=2proc-ui \
    --real-ui-campaign=accepted-friend-inline >"$REAL_UI_INLINE_PLAN" \
    2>"$TMP_ROOT/real_ui_inline.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["handshake", "message"]
    ' "$REAL_UI_INLINE_PLAN" >/dev/null; then
        pass "accepted-friend-inline campaign keeps handshake+message chained"
    else
        fail "accepted-friend-inline campaign keeps handshake+message chained"
    fi
    if jq -e '
        (.groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh")
        and ([.groups[0].commands[] | select(contains("reset_friendship"))]
            | length == 0)
    ' "$REAL_UI_INLINE_PLAN" >/dev/null; then
        pass "accepted-friend-inline plan-json reuses one fresh launch without resets"
    else
        fail "accepted-friend-inline plan-json reuses one fresh launch without resets"
    fi
else
    fail "accepted-friend-inline plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_inline.err" "$REAL_UI_INLINE_PLAN" 2>/dev/null)"
fi

REAL_UI_CHAIN_DRY="$TMP_ROOT/real_ui_chain_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=handshake,message \
    >"$REAL_UI_CHAIN_DRY" 2>"$TMP_ROOT/real_ui_chain.err"; then
    CHAIN_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_CHAIN_DRY" || true)"
    CHAIN_HANDSHAKE_LINE="$(grep -n 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CHAIN_DRY" | head -n1 | cut -d: -f1)"
    CHAIN_MESSAGE_LINE="$(grep -n 'drive_real_ui_pair.dart message ' "$REAL_UI_CHAIN_DRY" | head -n1 | cut -d: -f1)"
    if [[ "$CHAIN_LAUNCH_COUNT" -eq 1 && -n "$CHAIN_HANDSHAKE_LINE" && -n "$CHAIN_MESSAGE_LINE" \
        && "$CHAIN_HANDSHAKE_LINE" -lt "$CHAIN_MESSAGE_LINE" ]]; then
        pass "handshake+message replay stays on one real-UI launch"
    else
        fail "handshake+message replay stays on one real-UI launch" \
            "expected a single launch with handshake before message, but saw $CHAIN_LAUNCH_COUNT launches"
    fi
else
    fail "real-UI handshake+message dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_chain.err" "$REAL_UI_CHAIN_DRY" 2>/dev/null)"
fi

REAL_UI_MESSAGE_PLAN="$TMP_ROOT/real_ui_message_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-scenario=message \
    >"$REAL_UI_MESSAGE_PLAN" 2>"$TMP_ROOT/real_ui_message.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["message"]
    ' "$REAL_UI_MESSAGE_PLAN" >/dev/null; then
        pass "message-only plan-json narrows to the requested scenario"
    else
        fail "message-only plan-json narrows to the requested scenario"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0]
            == "TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_MESSAGE_PLAN" >/dev/null; then
        pass "message-only plan-json restores the friended baseline instead of re-handshaking"
    else
        fail "message-only plan-json restores the friended baseline instead of re-handshaking"
    fi
else
    fail "message-only plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_message.err" "$REAL_UI_MESSAGE_PLAN" 2>/dev/null)"
fi

REAL_UI_NO_FRIEND_PLAN="$TMP_ROOT/real_ui_no_friend_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-campaign=fresh-no-friend \
    >"$REAL_UI_NO_FRIEND_PLAN" 2>"$TMP_ROOT/real_ui_no_friend.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["decline"]
    ' "$REAL_UI_NO_FRIEND_PLAN" >/dev/null; then
        pass "fresh-no-friend campaign maps to the decline-only branch"
    else
        fail "fresh-no-friend campaign maps to the decline-only branch"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_NO_FRIEND_PLAN" >/dev/null; then
        pass "fresh-no-friend plan-json stays on a fresh no-friend launch"
    else
        fail "fresh-no-friend plan-json stays on a fresh no-friend launch"
    fi
else
    fail "fresh-no-friend plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_no_friend.err" "$REAL_UI_NO_FRIEND_PLAN" 2>/dev/null)"
fi

REAL_UI_NO_FRIEND_CALL_PLAN="$TMP_ROOT/real_ui_no_friend_call_plan.json"
if run_runner --plan-json --class=2proc-ui \
    --real-ui-campaign=no-friend-inline-call >"$REAL_UI_NO_FRIEND_CALL_PLAN" \
    2>"$TMP_ROOT/real_ui_no_friend_call.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == ["custom_message", "handshake", "call_voice"]
    ' "$REAL_UI_NO_FRIEND_CALL_PLAN" >/dev/null; then
        pass "no-friend-inline-call campaign preserves the expected custom-message -> handshake -> call chain"
    else
        fail "no-friend-inline-call campaign preserves the expected custom-message -> handshake -> call chain"
    fi
    if jq -e '
        (.groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh")
        and ([.groups[0].commands[] | select(contains("reset_friendship"))]
            | length == 0)
    ' "$REAL_UI_NO_FRIEND_CALL_PLAN" >/dev/null; then
        pass "no-friend-inline-call stays on one launch without extra reset maintenance"
    else
        fail "no-friend-inline-call stays on one launch without extra reset maintenance"
    fi
else
    fail "no-friend-inline-call plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_no_friend_call.err" "$REAL_UI_NO_FRIEND_CALL_PLAN" 2>/dev/null)"
fi

REAL_UI_CALL_DRY="$TMP_ROOT/real_ui_call_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call \
    >"$REAL_UI_CALL_DRY" 2>"$TMP_ROOT/real_ui_call.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CALL_DRY" \
        && grep -q 'drive_real_ui_pair.dart message ' "$REAL_UI_CALL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_CALL_DRY"; then
        pass "accepted-friend-inline-call campaign expands call reuse after messaging"
    else
        fail "accepted-friend-inline-call campaign expands call reuse after messaging"
    fi
    CALL_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_CALL_DRY" || true)"
    if [[ "$CALL_LAUNCH_COUNT" -eq 1 ]]; then
        pass "accepted-friend-inline-call stays on one launch"
    else
        fail "accepted-friend-inline-call stays on one launch" \
            "expected 1 launch but saw $CALL_LAUNCH_COUNT"
    fi
else
    fail "accepted-friend-inline-call dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call.err" "$REAL_UI_CALL_DRY" 2>/dev/null)"
fi

REAL_UI_CUSTOM_DRY="$TMP_ROOT/real_ui_custom_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-scenario=custom_message \
    >"$REAL_UI_CUSTOM_DRY" 2>"$TMP_ROOT/real_ui_custom.err"; then
    if grep -q 'drive_real_ui_pair.dart custom_message ' "$REAL_UI_CUSTOM_DRY" \
        && ! grep -q 'TOXEE_FIXTURE_C_RESTORE=paired_for_e2e' "$REAL_UI_CUSTOM_DRY"; then
        pass "custom_message scenario stays on a fresh no-friend launch"
    else
        fail "custom_message scenario stays on a fresh no-friend launch"
    fi
else
    fail "custom_message dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_custom.err" "$REAL_UI_CUSTOM_DRY" 2>/dev/null)"
fi

REAL_UI_EXPANDED_DRY="$TMP_ROOT/real_ui_expanded_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=all-expanded \
    >"$REAL_UI_EXPANDED_DRY" 2>"$TMP_ROOT/real_ui_expanded.err"; then
    if grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_EXPANDED_DRY" \
        && grep -q 'drive_real_ui_pair.dart custom_message ' "$REAL_UI_EXPANDED_DRY"; then
        pass "all-expanded campaign includes the newly merged reusable cases"
    else
        fail "all-expanded campaign includes the newly merged reusable cases"
    fi
    EXPANDED_LAUNCH_COUNT="$(grep -c 'launch_fixture_c_pair.sh' "$REAL_UI_EXPANDED_DRY" || true)"
    EXPANDED_RESET_COUNT="$(grep -c 'drive_real_ui_pair.dart reset_friendship ' "$REAL_UI_EXPANDED_DRY" || true)"
    if [[ "$EXPANDED_LAUNCH_COUNT" -eq 1 && "$EXPANDED_RESET_COUNT" -eq 2 ]]; then
        pass "all-expanded dry-run stays on one launch and inserts two reset maintenance steps"
    else
        fail "all-expanded dry-run stays on one launch and inserts two reset maintenance steps" \
            "expected 1 launch / 2 resets, saw $EXPANDED_LAUNCH_COUNT launch(es) / $EXPANDED_RESET_COUNT reset(s)"
    fi
else
    fail "all-expanded campaign dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_expanded.err" "$REAL_UI_EXPANDED_DRY" 2>/dev/null)"
fi

REAL_UI_EXPANDED_PLAN="$TMP_ROOT/real_ui_expanded_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-campaign=all-expanded \
    >"$REAL_UI_EXPANDED_PLAN" 2>"$TMP_ROOT/real_ui_expanded_plan.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios
        == [
            "handshake",
            "message",
            "message_burst",
            "call_voice",
            "call_reject",
            "custom_message",
            "handshake_detail",
            "decline"
        ]
    ' "$REAL_UI_EXPANDED_PLAN" >/dev/null; then
        pass "all-expanded plan-json preserves the expanded scenario catalog order"
    else
        fail "all-expanded plan-json preserves the expanded scenario catalog order"
    fi
    if jq -e '
        (.groups[0].commands[0] == "tool/mcp_test/launch_fixture_c_pair.sh")
        and ([.groups[0].commands[] | select(contains("reset_friendship"))]
            | length == 2)
    ' "$REAL_UI_EXPANDED_PLAN" >/dev/null; then
        pass "all-expanded plan-json shows a single launch plus explicit reset maintenance"
    else
        fail "all-expanded plan-json shows a single launch plus explicit reset maintenance"
    fi
else
    fail "all-expanded plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_expanded_plan.err" "$REAL_UI_EXPANDED_PLAN" 2>/dev/null)"
fi

REAL_UI_BURST_DRY="$TMP_ROOT/real_ui_burst_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-burst \
    >"$REAL_UI_BURST_DRY" 2>"$TMP_ROOT/real_ui_burst.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_BURST_DRY" \
        && grep -q 'drive_real_ui_pair.dart message_burst ' "$REAL_UI_BURST_DRY"; then
        pass "accepted-friend-inline-burst campaign expands burst messaging reuse"
    else
        fail "accepted-friend-inline-burst campaign expands burst messaging reuse"
    fi
else
    fail "accepted-friend-inline-burst dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_burst.err" "$REAL_UI_BURST_DRY" 2>/dev/null)"
fi

REAL_UI_CALL_REJECT_DRY="$TMP_ROOT/real_ui_call_reject_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-inline-call-reject \
    >"$REAL_UI_CALL_REJECT_DRY" 2>"$TMP_ROOT/real_ui_call_reject.err"; then
    if grep -q 'drive_real_ui_pair.dart handshake ' "$REAL_UI_CALL_REJECT_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_reject ' "$REAL_UI_CALL_REJECT_DRY"; then
        pass "accepted-friend-inline-call-reject campaign expands reject-call reuse"
    else
        fail "accepted-friend-inline-call-reject campaign expands reject-call reuse"
    fi
else
    fail "accepted-friend-inline-call-reject dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call_reject.err" "$REAL_UI_CALL_REJECT_DRY" 2>/dev/null)"
fi

REAL_UI_CALL_REJECT_PLAN="$TMP_ROOT/real_ui_call_reject_plan.json"
if run_runner --plan-json --class=2proc-ui --real-ui-scenario=call_reject \
    >"$REAL_UI_CALL_REJECT_PLAN" 2>"$TMP_ROOT/real_ui_call_reject_plan.err"; then
    if jq -e '
        .groups[0].entries[0].realUiScenarios == ["call_reject"]
    ' "$REAL_UI_CALL_REJECT_PLAN" >/dev/null; then
        pass "call_reject plan-json narrows to the requested scenario"
    else
        fail "call_reject plan-json narrows to the requested scenario"
    fi
    if jq -e '
        (.groups[0].commands | length) == 3
        and .groups[0].commands[0]
            == "TOXEE_FIXTURE_C_RESTORE=paired_for_e2e tool/mcp_test/launch_fixture_c_pair.sh"
    ' "$REAL_UI_CALL_REJECT_PLAN" >/dev/null; then
        pass "call_reject plan-json restores the friended baseline"
    else
        fail "call_reject plan-json restores the friended baseline"
    fi
else
    fail "call_reject plan-json exits 0" \
        "$(cat "$TMP_ROOT/real_ui_call_reject_plan.err" "$REAL_UI_CALL_REJECT_PLAN" 2>/dev/null)"
fi

REAL_UI_FULL_DRY="$TMP_ROOT/real_ui_full_dry.out"
if run_runner --dry-run --class=2proc-ui --real-ui-campaign=accepted-friend-detail-full \
    >"$REAL_UI_FULL_DRY" 2>"$TMP_ROOT/real_ui_full.err"; then
    if grep -q 'drive_real_ui_pair.dart message_burst ' "$REAL_UI_FULL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_voice ' "$REAL_UI_FULL_DRY" \
        && grep -q 'drive_real_ui_pair.dart call_reject ' "$REAL_UI_FULL_DRY"; then
        pass "accepted-friend-detail-full campaign chains common chat and call cases"
    else
        fail "accepted-friend-detail-full campaign chains common chat and call cases"
    fi
else
    fail "accepted-friend-detail-full dry-run exits 0" \
        "$(cat "$TMP_ROOT/real_ui_full.err" "$REAL_UI_FULL_DRY" 2>/dev/null)"
fi

SUITE_DRY="$TMP_ROOT/suite_dry.out"
if run_suite --dry-run --tier=non-media >"$SUITE_DRY" 2>"$TMP_ROOT/suite_dry.err"; then
    if grep -q 'drive_fixture_c_pair.dart' "$SUITE_DRY" \
        && grep -q 'drive_real_ui_pair.dart handshake ' "$SUITE_DRY"; then
        pass "run_fixture_c_suite.sh delegates dry-run to the unified runner"
    else
        fail "run_fixture_c_suite.sh delegates dry-run to the unified runner" \
            "expected unified runner dry-run output"
    fi
else
    fail "run_fixture_c_suite.sh dry-run exits 0" \
        "$(cat "$TMP_ROOT/suite_dry.err" "$SUITE_DRY" 2>/dev/null)"
fi

set +e
run_non_media_alias --dry-run --tier=media >"$TMP_ROOT/non_media_alias_bad.out" 2>&1
BAD_ALIAS_CODE=$?
set -e
if [[ "$BAD_ALIAS_CODE" -eq 64 ]]; then
    pass "run_fixture_c_non_media.sh still rejects non-non-media tiers"
else
    fail "run_fixture_c_non_media.sh still rejects non-non-media tiers" \
        "got $BAD_ALIAS_CODE"
fi

set +e
run_runner --tier=bogus >"$TMP_ROOT/bad_tier.out" 2>&1
BAD_TIER_CODE=$?
set -e
if [[ "$BAD_TIER_CODE" -eq 64 ]]; then
    pass "invalid tier exits 64"
else
    fail "invalid tier exits 64" "got $BAD_TIER_CODE"
fi

if run_runner --validate-only >"$TMP_ROOT/validate.out" 2>&1; then
    pass "--validate-only exits 0"
else
    fail "--validate-only exits 0" "$(cat "$TMP_ROOT/validate.out")"
fi

echo
if (( FAIL_COUNT == 0 )); then
    printf 'Unified Fixture C runner regressions: PASS (%d checks)\n' "$PASS_COUNT"
else
    printf 'Unified Fixture C runner regressions: FAIL (%d failed, %d passed)\n' \
        "$FAIL_COUNT" "$PASS_COUNT"
fi
exit "$FAIL_COUNT"
