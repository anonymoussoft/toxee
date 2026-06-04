# S114 — Friend profile: conversation mute switch (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed) history=seeded`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned for the real-tap path (the `Switch.onChanged` → `_setC2CReceiveOpt` → `setC2CReceiveMessageOpt` + UIKit conversation-cache write needs the real engine + Prefs); the OS-banner-suppression PROOF stays the two-process `run_fixture_c_mute.sh` (S83). The setting round-trip is an L1/L2 candidate behind a seam.
**Status**: covered (data-half gate exists — `l3_recvopt_mute_toggle` proves `conversations[].recvOpt` 0→2→0; the real mute-switch tap is L3 / L1 WidgetTester candidate, not yet a runnable UI gate)

> Real-tap upgrade of S83's setting half. S83's runner gate drives `l3_set_c2c_recv_opt` directly; S114 drives the actual Do-Not-Disturb `Switch` so `_setC2CReceiveOpt(true)` and the UIKit conversation-cache `recvOpt` write are exercised through a real tap.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline), seeded C2C history (so a `c2c_<toxF>` conversation row exists and hydrates into `UikitDataFacade.conversationList`). Restore wipes existing state; cache miss auto-regenerates.
- Account A logged in, plaintext, sidebar Online (poll ≤60s).
- The C2C conversation `c2c_<toxF>` is present and hydrated in `l3_dump_state.conversations[]` (the list is UI-live and hydrates AFTER login — POLL `state_contains` for `<toxF prefix>` before asserting, per l3_debug_tools.dart:3633-3636).
- Pre-test `recvOpt == 0` for `c2c_<toxF>` (un-muted "before" state — `V2TIM_RECEIVE_NORMAL_MESSAGE=0`), so A2's flip to `2` is observable. The switch's `disturb` flag is initialized from the conversation's receive-opt at tencent_cloud_chat_user_profile_body.dart:481.
- The mute switch is the `Switch` in the profile body's Do-Not-Disturb row (`tL10n.doNotDisturb`).

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart --only L3-recvopt-mute-toggle
```

`tool/mcp_test/scenarios/l3_recvopt_mute_toggle.json` is the hermetic data-half: it waits for the seeded conversation to hydrate and to NOT already carry `recvOpt: 2`, calls `set_recv_opt {opt: 2}` (= `l3_set_c2c_recv_opt`), asserts `state{field: conversations, contains: "recvOpt: 2"}`, then restores `opt: 0` and asserts `notContains: "recvOpt: 2"`. `recvOpt == 2` is the exact input `_shouldSuppress` reads (notification_message_listener.dart:224). It does NOT tap the `Switch` — that real-tap leg is the S114 UI Driver below and has no runnable UI gate yet. The OS-banner-absence proof remains the two-process `tool/mcp_test/run_fixture_c_mute.sh` (S83).

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`).
2. Tap F's row `marionette.tap(UiKeys.contactListTile(<toxF>))` (`contact_list_item:<toxF>`) → push `TencentCloudChatUserProfile`. Confirm `UiKeys.userProfileFriendNameText` shows F's name.
3. Scroll to the Do-Not-Disturb row if needed; tap `UiKeys.userProfileConversationMuteSwitch` (`user_profile_conversation_mute_switch`) — the `Switch` at tencent_cloud_chat_user_profile_body.dart:572-575. Its `onChanged(true)` calls `_setC2CReceiveOpt(true)` → `setC2CReceiveMessageOpt(opt=V2TIM_RECEIVE_NOT_NOTIFY_MESSAGE)`, persisted as `recvOpt=2` and pushed into `UikitDataFacade.conversationList[i].recvOpt`.
4. Poll `l3_dump_state.conversations[]` for `recvOpt: 2` on `c2c_<toxF>` (the cache write is synchronous-ish but the dump reflects the live UIKit store).
5. RESTORE (cleanup): tap the same `Switch` again → `_setC2CReceiveOpt(false)` → `recvOpt=0`. Leave the fixture un-muted so it self-cleans (mirrors the runner gate's final `opt: 0` restore).

## Assertions
- A1 (pre-mute, control): after the hydrate poll, `l3_dump_state.conversations[]` entry for `c2c_<toxF>` has `recvOpt == 0` (or absent-as-0); the dump does NOT contain `recvOpt: 2`.
- A2 (primary, post-toggle-on): `l3_dump_state.conversations[]` entry for `c2c_<toxF>` has `recvOpt == 2` — the SAME observable the data-half gate asserts (`state{field: conversations, contains: "recvOpt: 2"}`, l3_recvopt_mute_toggle.json:10). This is exactly the value `_shouldSuppress` treats as "suppress" (`recvOpt != 0`).
- A3 (display reflects state): the `Switch` `value` is `true` after toggle (the body's `disturb` flag, recomputed from `recvOpt == 2`).
- A4 (restore): after the second tap, `recvOpt` returns to `0` and the dump no longer contains `recvOpt: 2` (the runner-gate final assertion, l3_recvopt_mute_toggle.json:14).
- A5: `official.get_runtime_errors({})` empty vs the Step-1 baseline; no `setFailed` notification on the un-mute restore.

## Notes
- L3-pin reason: the OS-notification-suppression PROOF (a real inbound from a twin + `log stream` banner absence) is two-process + OS-gated (S83 A4/A5) and out of scope here; S114 proves only the `recvOpt` setting via the real switch tap. The setting round-trip itself is L1/L2-promotable behind a seam.
- Key verified: `user_profile_conversation_mute_switch` @ tencent_cloud_chat_user_profile_body.dart:574 (raw `ValueKey` on the `Switch`).
- Sibling distinction: S83 = the full mute→inbound→banner-suppression two-process scenario (setting half hermetically gated); S114 = the real-tap upgrade of just the setting half via the profile-body switch. The conversation-context-menu mute path (if any) is a separate surface.
- `recvOpt` semantics: 0 = receive+notify, 1 = no-notify, 2 = block/mute. The switch WRITES 2 and its on-state reads `== 2`; `_shouldSuppress` suppresses on `!= 0`. Always restore to 0 so the seeded fixture stays clean.
- Mobile parity: the Do-Not-Disturb switch lives in the SHARED `tencent_cloud_chat_user_profile_body.dart` (no platform split) — iOS/Android hit the same key and the same `_setC2CReceiveOpt` path, so this scenario covers mobile via the same anchor.
- `l3_dump_state.conversations[]` is UI-live and hydrates AFTER login; always POLL `state_contains` for the conversation before asserting `recvOpt`, never read a cold dump immediately after navigation.
