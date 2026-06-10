# S111 — Friend profile: clear chat history + confirm dialog

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed, ≥3 persisted C2C messages) history=seeded`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned for the real-UI tap path (UIKit profile body + adaptive confirm dialog mount under the real engine); the data-half is hermetic and already gated. The destructive `clearC2CHistoryMessage` + dialog confirm is a WidgetTester (L1) candidate once the profile body can be mounted behind a seam.
**Status**: covered — the real-UI tap path is covered at the widget layer (L1): the destructive clear-history row opens the real adaptive confirm dialog, Cancel dispatches nothing, Confirm dispatches the production `clearC2CHistoryMessage(userID)` (captured at the `TencentCloudChatSdkPlatform` routing layer) and dismisses the dialog. The data-half (`l3_clear_history` proves messageCount→0) remains covered by the L3 scenario.
**Covered-by**: test/ui/contact/friend_profile_ops_real_ui_test.dart (S111 widget-layer tap + dialog), tool/mcp_test/scenarios/l3_clear_history.json (data-half)

> Real-UI upgrade of the `l3_clear_history` reset primitive. That gate drives `clear_history` directly; S111 drives it through the actual friend-profile destructive row + confirm dialog so the upper row (`deleteAllMessages`) is exercised distinctly from the lower delete-friend row (S112).

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (the echo peer, Offline since the bot isn't running), chat history = 3 ping/pong pairs. Restore wipes existing toxee state; on cache miss it auto-calls `regen_echo_peer_seed.sh`.
- Account A logged in, plaintext, sidebar Online (poll ≤60s).
- `Prefs.local_friends_<toxA_prefix16>` contains `<toxF>` (`_kLocalFriends='local_friends'`, scoped via `Prefs._scopedKey` first-16-of-toxA).
- The C2C conversation `c2c_<toxF>` has ≥1 persisted message in `l3_dump_state` (`messageCount > 0`) before the run, so A2's drop to `0` is observable, not a no-op.
- The clear-history row is the UPPER destructive row (`tL10n.deleteAllMessages` / "清除聊天记录"), NOT the lower delete-friend row — disambiguated by `UiKeys.userProfileClearHistoryButton` vs `UiKeys.userProfileDeleteFriendButton` (S112).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart --only L3-clear-history
```

`tool/mcp_test/scenarios/l3_clear_history.json` is the hermetic data-half: it sends 3 self texts carrying a per-run `{{nonce}}`, waits for the last to persist, calls the `clear_history` action (= `l3_clear_history`), then asserts each text's `message_count_text == 0` AND the conversation-wide `state{field: messageCount, equals: 0}`. This proves the clear path empties persistence. It does NOT tap the profile-body destructive row or mount the confirm dialog — that leg is now covered at the widget layer (L1) by `test/ui/contact/friend_profile_ops_real_ui_test.dart` (row tap → real confirm dialog → cancel/confirm legs); the live-engine walkthrough below remains the L3 variant.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`); wait for the Contacts tab.
2. Tap F's row `marionette.tap(UiKeys.contactListTile(<toxF>))` (`contact_list_item:<toxF>`) → pushes `TencentCloudChatUserProfile`. Confirm `UiKeys.userProfileFriendNameText` (`user_profile_friend_name_text`) shows F's name.
3. Tap the clear-history row `UiKeys.userProfileClearHistoryButton` (`user_profile_clear_history_button`). It is a `GestureDetector` (tencent_cloud_chat_user_profile_body.dart:713-714) — `fmt_tap_widget` may no-op (no `Semantics.onTap`); use marionette key tap. It calls `showClearChatHistoryDialog`.
4. The adaptive confirm dialog mounts (title `tL10n.clearMsgTip`). Tap `UiKeys.userProfileClearHistoryConfirmButton` (`user_profile_clear_history_confirm_button`) — the `tL10n.confirm` `TextButton` at line 638 that pops `true` and calls `onClearChatHistory()` → `clearC2CHistoryMessage(userID: <toxF>)` then `clearMessageList`.
5. To make the C2C `messages[]`/`messageCount` block populate for A2, open the F conversation first (so `ffi.activePeerId == <toxF>`) OR pass `{conversationId: "c2c_<toxF>"}` to `l3_dump_state`. `l3_dump_state`'s C2C block only emits `messageCount`/`messages[]` for a resolved target (l3_debug_tools.dart:3726-3728, 3779-3782).

## Assertions
- A1 (pre-clear, control): with `c2c_<toxF>` resolved, `l3_dump_state.messageCount > 0` and `messages[]` is non-empty (the seed's 3 pairs).
- A2 (primary, post-confirm): `l3_dump_state {conversationId: "c2c_<toxF>"}` returns `messageCount == 0` and `messages[]` empty — same observable the data-half gate's `state{field: messageCount, equals: 0}` asserts (l3_clear_history.json:18).
- A3 (cancel path is distinct): tapping the dialog's Cancel `TextButton` (line 633-635, `Navigator.pop()` with no `onClearChatHistory`) leaves `messageCount` unchanged — a B-variant, NOT asserted in the happy-path run.
- A4 (friendship intact — discriminator vs S112): after clear, `l3_dump_state.friends[]` still contains `<toxF>` and `friendCount` is unchanged; `Prefs.local_friends_<toxA_prefix16>` still contains `<toxF>`. Clear-history is NOT unfriend.
- A5: `official.get_runtime_errors({})` empty vs the Step-1 baseline; no `FATAL`/`terminate called`.

## Notes
- L3-pin reason: the real confirm-dialog mount + `clearC2CHistoryMessage` round-trip needs the real Flutter engine + Hive persistence (L2/L3); the hermetic `l3_clear_history` gate already covers the data observable, so this stays a UI-tap upgrade, not a new executable gate.
- Keys verified: `user_profile_clear_history_button` @ tencent_cloud_chat_user_profile_body.dart:714; `user_profile_clear_history_confirm_button` @ :638. Both raw `ValueKey('…')`, matched by `find.byKey` and marionette `tap({key:'…'})`.
- Sibling distinction: S111 = upper clear-history row; S28/S112 = lower delete-friend row. The two destructive rows have distinct anchors (S28 Notes) so no row-order disambiguation is needed.
- Destructive: the clear-history confirm is gated behind `user_profile_clear_history_confirm_button`; never assert A2 without first tapping confirm (the GestureDetector tap only OPENS the dialog).
- Mobile parity: `tencent_cloud_chat_user_profile_body.dart` is the SHARED UIKit profile body (no `_desktop`/`_mobile` split) — the clear-history row + dialog exist identically on iOS/Android, so this scenario covers mobile via the same keys.
- `l3_dump_state` C2C `messages[]`/`messageCount` only populate for a RESOLVED conversation (active peer or explicit `conversationId`); always pass `conversationId: "c2c_<toxF>"` for A1/A2 rather than reading a bare dump.
