# S35 — Leave a group

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] quit_groups=empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because covers cold-restart `RejoinKnownGroups` invariant (kill + relaunch)
**Status**: covered

## Precondition
- One signed-in account A; exactly one pre-joined group `<gidG>` with non-empty `Prefs.group_name_<gidG>` (e.g. `"S35 victim group"`).
- A is a **joined member**, not owner — owner variant calls `dismissGroup`, different log markers.
- `Prefs.quit_groups_list:<toxA>` empty or absent.
- `MCP_BINDING=marionette` (avatar/header tap has no label).

## Driver
1. Tap conversation row for G by `UiKeys.groupListTile("<gidG>")` (`group_list_tile:<gidG>`). Semantic-ref / label match remains the fallback if the fixture does not know `<gidG>` until runtime.
2. Tap chat header avatar — opens `TencentCloudChatGroupProfile` with toxee's `_ToxeeGroupProfileDeleteButton` rendering two red rows.
3. Tap `UiKeys.groupProfileLeaveButton` (`group_profile_leave_button`) — this is the **lower** destructive row (`tL10n.quit` / `退出` or `tL10n.dissolve` for owner variants), not the upper clear-history row.
4. Confirm dialog mounts (title `tL10n.quitGroupTip`); tap `tL10n.confirm` button.
5. After UI settles: kill app, relaunch, reconnect MCP, wait for HomePage online.

## Assertions
- Before: conversation list contains G's row; after confirm + ≤15s settle: G's row is gone (no `group_<gidG>` row).
- Log markers (eager Dart path): `[FfiChatService] quitGroup: ENTRY - groupId=<gidG>` → `Received callback result: code=0` → `Removing from _knownGroups` → `Adding to _quitGroups` → `Group history cleared` → `quitGroup: COMPLETE`.
- `[FakeChatDataProvider] Removed conversation group_<gidG> from UIKit conversation list via FakeGroupDeleted event` appears.
- `defaults read com.toxee.app 'flutter.groups':<toxA>` no longer contains `<gidG>`.
- `defaults read com.toxee.app 'flutter.quit_groups_list':<toxA>` contains `<gidG>`.
- **Cold-restart invariant**: after kill + relaunch, sidebar has no row for G; `quit_groups_list` still contains `<gidG>`; `FfiChatService._knownGroups` does NOT contain `<gidG>`.
- Negative grep AFTER quitGroup COMPLETE: `[HomeGroupController] handleGroupChanged: groupId=<gidG>`, `init: RejoinKnownGroups returned:.*<gidG>`, `_onGroupAdded: <gidG>` must not appear.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- The two destructive rows now have stable keys: `group_profile_clear_history_button` (upper) and `group_profile_leave_button` (lower). Owner-of-non-Work still reuses the same lower row but labels it `Dissolve`.
- `_handleQuitGroup` calls `Prefs.addQuitGroup` and `conversationManager.deleteConversation` **eagerly** (before C++ callback) — this defends against the historical bug where restart-during-leave lost the quit_groups entry. The C++ `cleanupGroupState` callback is idempotent (soft A8).
- Owner-of-non-Work case shows `tL10n.dissolve` and calls `dismissGroup`; out of scope for this fixture.
- Confirm dialog is `CupertinoAlertDialog` on macOS (showAdaptiveDialog).
- Cancel-path negative variant (tap leave row → cancel → group still present) tracked as separate S35-cancel.
