# S122 — Group profile: Clear group history + confirm (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded(self-sends)`
**Harness mode**: peerHarness=none (creating + self-seeding + clearing a group is hermetic single-instance)
**Promotion target**: L1 WidgetTester for the clear-button-tap → confirm-dialog state machine; the group-history DATA round-trip is **needs-new-tool** (no `l3_clear_group_history` exists today).
**Status**: covered — LIVE-VALIDATED 2026-06-08 by the two-process real-UI gate. The "needs-new-tool" gap is closed: a new ungated `l3_clear_group_history` tool (`l3_debug_tools.dart`) calls `ffi.clearGroupHistory` — the group counterpart to the still-C2C-only `l3_clear_history` (which keeps rejecting group ids with `group_unsupported`). The `group_clear_history` gate (`drive_real_ui_pair.dart`, campaign `group-clear-history`) establishes a two-process private group, has B send so A holds REAL group history, asserts A's group `messageCount>0`, clears via `l3_clear_group_history`, then asserts `messageCount→0` while the conversation ROW survives (rebuilt from `knownGroups`, independent of history). **Live: PASS (before=1 → emptied, row survives, gid=tox_1).** The product UI clear button (`group_profile_clear_history_button` → `clearGroupHistoryMessage`) drives the SAME `ffi.clearGroupHistory`; the l3 tool gates the data half deterministically without the flutter_skill-unreachable profile route. The row-survives + pin-survives invariant is additionally gated by S154. Shared desktop+mobile. See [[real_ui_group_message_fresh_nontest]].

> Real-UI-only scenario. There is no hermetic data-half gate: the C2C `l3_clear_history` tool refuses `group_` ids. The group clear-history CONTROL is keyed and live (the dialog → `clearGroupHistoryMessage` → `ffi.clearGroupHistory` path runs), but the runner can only SET UP and READ group history via `l3_send_group_text` + `l3_dump_state{conversationId:'group_<gidG>'}` — it cannot drive the clear. So this is a marionette tap with a dump-state before/after readout, not a `run_l3_scenarios.dart` gate.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- One signed-in account A; one joined group `<gidG>`. Hermetic seed: `l3_create_group {name:'S122 clear'}` → `<gidG>` (in `l3_dump_state.knownGroups`, `l3_debug_tools.dart:3672`).
- **Seed self-sends**: `l3_send_group_text {groupId:'<gidG>', text:'S122 m1'}` ×N, so the group's history is non-empty. Verify `l3_dump_state {conversationId:'group_<gidG>'}.messages` has N entries (the group-history readout, `l3_debug_tools.dart:2562`, `:3759`).
- Account A logged in, plaintext, sidebar Online (poll `<nick>\nOnline` ≤60s).
- `MCP_BINDING=marionette` — the header tap opening the group profile has no label; the clear-history row is keyed.
- Pinned state of `<gidG>` is irrelevant; clear-history must NOT unpin (the override clears history directly without `deleteConversation` to preserve the pinned flag, `lib/ui/group/group_builder_override.dart:704-707`).

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)`; baseline `official.get_runtime_errors({})`. Confirm `l3_dump_state {conversationId:'group_<gidG>'}.messages.length == N` (non-empty seed).
2. Tap the group row by `UiKeys.groupListTile("<gidG>")` (`group_list_tile:<gidG>`, `ui_keys.dart:157`); ref/label fallback for runtime-discovered gids.
3. Tap the chat panel header → pushes `TencentCloudChatGroupProfile` (no key; tap by ref).
4. Tap `UiKeys.groupProfileClearHistoryButton` (`group_profile_clear_history_button`) — the **upper** destructive row (label `tL10n.deleteAllMessages`), `lib/ui/group/group_builder_override.dart:796`. This is the `GestureDetector.onTap: _showClearChatHistoryDialog`.
5. The confirm dialog mounts (title `tL10n.clearMsgTip`, `showAdaptiveDialog`, `group_builder_override.dart:676-694`). Tap the `tL10n.confirm` TextButton (`:686`) — fires `_onClearChatHistory`.
6. After UI settles (≤5s), poll `l3_dump_state {conversationId:'group_<gidG>'}.messages`.

## Assertions
- A1 (seeded baseline): Step 1 — `l3_dump_state {conversationId:'group_<gidG>'}.messages.length == N` (> 0); `official.get_runtime_errors({})` empty.
- A2 (confirm dialog mounts): after Step 4, a dialog with title `clearMsgTip` is in the tree, with cancel + confirm TextButtons (`group_builder_override.dart:680-692`).
- A3 (history emptied, primary): after Step 6, `l3_dump_state {conversationId:'group_<gidG>'}.messages` is empty (`length == 0`). This is the observable outcome of `_onClearChatHistory` → `clearGroupHistoryMessage` (code==0) → `ffi.clearGroupHistory(groupID)` + `clearMessageBuffer('group_<gidG>')` + `refreshConversations` (`group_builder_override.dart:696-723`).
- A4 (conversation survives, pinned-safe): the group row is STILL present — `l3_dump_state.conversationIds` still contains `group_<gidG>` (`:3659`); clear-history wipes messages but does NOT delete the conversation or unpin it (`group_builder_override.dart:704-707`). Distinguishes clear-history from leave (S123, which removes the conversation).
- A5: `official.get_runtime_errors({})` matches the Step-1 baseline; negative grep: `[GroupProfile] _onClearChatHistory: persistence cleanup failed` (`group_builder_override.dart:718`) MUST NOT appear (logs only on failure).

## Notes
- **Honest gate status**: NO data-half runner gate. `l3_clear_history` is C2C-only and rejects `group_` ids (`l3_debug_tools.dart:1251`). The group clear path runs only through the real UI here; the executable runner can seed (`l3_send_group_text`) and read (`l3_dump_state{conversationId}`) group history but cannot trigger the clear. Promotion = L1 WidgetTester (dialog state machine) OR a new `l3_clear_group_history` tool (coverage map line 651-653 notes the read-half `conversations[].recvOpt`/messages already exist, only the clear/set tool is missing).
- Key verified: `groupProfileClearHistoryButton` @ `lib/ui/group/group_builder_override.dart:796` (defined `ui_keys.dart:170`); confirm dialog `_showClearChatHistoryDialog` @ `:676`, title `clearMsgTip`.
- Sibling distinction: S122 = clear-history (upper row, keeps conversation); S123 = leave (lower row, removes conversation). The two destructive rows share `colorTheme.contactRefuseButtonColor` styling but distinct keys.
- Mobile parity: the clear-history row lives in the SHARED `_ToxeeGroupProfileDeleteButton` (`lib/ui/group/group_builder_override.dart`), so the keyed control + `_onClearChatHistory` path covers mobile.
- Do NOT mark "covered (executable)" — the only executable leg is the dump-state readout around a manual tap.
