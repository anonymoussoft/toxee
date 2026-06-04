# S84 — Pin / unpin a conversation

**Layer**: L3 (executable hermetic runner gate)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded`
**Harness mode**: single-instance L3 runner (no echo peer required — pinning is local Prefs state)
**Runner gate**: `tool/mcp_test/scenarios/l3_pin_toggle.json` via `dart run tool/mcp_test/run_l3_scenarios.dart` (hard gate, hermetic)
**Promotion target**: keyed toxee menu anchors now exist for promotion work (`conversation_context_menu_pin_item`, `conversation_context_menu_unpin_item`), but the hard gate remains L3 today because it intentionally drives the hermetic `FakeConversationManager.setPinned` path instead of depending on desktop right-click / long-press menu-open gesture coverage.
**Status**: covered (executable). Maps to feature **F2** (会话固定/取消, `FakeConversationManager.setPinned`, inventory §F.2).

## Precondition
- Account A signed in, online, plaintext profile; the seeded echo-peer C2C conversation present (`conversationID = c2c_3116CBE0…7244`).
- Pinned set starts **empty** (`Prefs.getPinned()` → `{}`). The gate's first step is a `state_contains pinnedConversations "[]"` precondition that fails loudly on a dirty fixture.
- App launched with the L3 surface: `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`.

## Driver (runner steps)
1. `wait_for state_contains pinnedConversations "[]"` — confirm the pinned set is empty (clean baseline).
2. `set_pinned { conversationId: "c2c_3116CBE0…7244", pinned: true }` → `l3_set_pinned` → `FakeConversationManager.setPinned(conversationID, true)` (`lib/sdk_fake/fake_managers.dart:285`) → `Prefs.setPinned` (`lib/util/prefs.dart:252`) + a pinned-first conversation-list re-emit.
3. `wait_for state_contains pinnedConversations "3116CBE0974181B6"` — the normalized peer key (case-preserving, `normalizeToxId`, `lib/util/tox_utils.dart:17`) entered the pinned set.
4. `set_pinned { conversationId: "c2c_3116CBE0…7244", pinned: false }` → unpin (restore).

## Assertions
- A1 (pinned mid-state, in-step): after Step 2 the pinned set contains the peer — `l3_dump_state.pinnedConversations` stringifies to include `3116CBE0974181B6` (Step 3 `wait_for` throws otherwise).
- A2 (per-item flag): `l3_dump_state.conversations[]` for the peer reports `isPinned: true` while pinned (UIKit list re-sort; `UikitDataFacade.conversationList`).
- A3 (unpin restores, final): after Step 4, `l3_dump_state.pinnedConversations == []` (`state{field:pinnedConversations, contains:"[]"}`) — the fixture self-cleans.
- A4 (race-free read): `pinnedConversations` is read from `Prefs.getPinned()` (the set `setPinned` writes **before** returning), not the async conversation-list re-emit, so the assertion can't race the UI refresh.

## Notes
- `setPinned` accepts both `c2c_<id>` and `group_<gid>` ids; this gate exercises the C2C leg. Group pinning shares the same tool/path (a future group gate can reuse `l3_set_pinned` with a `group_` id).
- The pinned store key for C2C is the **normalized bare** id (prefix stripped, truncated to 64, case preserved), so a `state{contains}` substring on the 16-char uppercase prefix matches.
- Hermetic: no DHT round-trip and no echo peer — `pinnedConversations` and the setter are pure local state, so this is a stable hard gate (the "cheap hermetic smoke" tier, not the flaky two-process tier).
- Real toxee menu anchors are now shipped for interactive coverage: `conversation_context_menu_pin_item` when the row is unpinned, `conversation_context_menu_unpin_item` when it is pinned, and `conversation_context_menu_delete_item` for the sibling destructive action.
