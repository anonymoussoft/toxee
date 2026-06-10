# S115 — Friend profile: "Send Message" tile → opens conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned for the real-tap navigation (the tile's `onNavigateToChat` → toxee `_onTapContactItem` route mounts the real message panel under the engine); the navigation-routing assertion is an L1/L2 candidate behind a seam once the contact-profile route is constructor-injectable.
**Status**: covered — the keying GAP is FIXED and the tap path is covered at the widget layer (L1): the fork's `TencentCloudChatUserProfileChatButton` now carries per-tile keys (`friend_profile_send_message_tile` / `friend_profile_voice_call_tile` / `friend_profile_video_call_tile`) on the tiles themselves, the gate demonstrates geometrically that the row center (where a whole-row `friendProfileSendMessageButton` key-tap lands) sits inside the middle VOICE tile and NOT the Send tile, and a tap on the keyed Send tile fires the production `onNavigateToChat` hook (alias of `onTapContactItem`) exactly once with the friend's userID and `groupID == null`. The live panel-mount observable (real message panel + composer under the engine) remains the L3 driver below.
**Covered-by**: test/ui/contact/friend_profile_ops_real_ui_test.dart (S115 per-tile key + navigate hook)

> Pure-UI navigation scenario: tapping the Send-Message tile on a friend profile opens that friend's C2C conversation. There is no `l3_*` data-half (the observable is "a chat panel mounted", not a Prefs/history mutation); `l3_dump_state.currentConversation` is the closest state readout.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — active account `echo_seeded_test` (auto-login on), 1 friend F (echo peer, Offline) with nickName `<nickF>`. Restore wipes existing state; cache miss auto-regenerates.
- Account A logged in, plaintext, sidebar Online (poll ≤60s).
- `Prefs.local_friends_<toxA_prefix16>` contains `<toxF>` (the tile group is toxee's `userProfileChatButtonBuilder` override, mounted for any profile).
- No chat open at start (`l3_dump_state.currentConversation == null`) so A2's flip to `c2c_<toxF>` is observable.

## Executable Driver

No data-half runner gate exists — this scenario asserts a UI navigation (a message panel mounting), not a persisted state mutation. The nearest state readout is `l3_dump_state.currentConversation` (set by the conversation-tap routing to `UikitDataFacade.currentConversation`, l3_debug_tools.dart:3702-3709), used in A2. There is no `l3_open_conversation`-style tool that bypasses the UI for this flow, so the tap IS the test.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`); baseline `official.get_runtime_errors({})`.
2. Tap F's row `marionette.tap(UiKeys.contactListTile(<toxF>))` (`contact_list_item:<toxF>`) → push `TencentCloudChatUserProfile`. Confirm `UiKeys.userProfileFriendNameText` shows `<nickF>`.
3. Drive the SEND tile specifically: tap its dedicated per-tile key `friend_profile_send_message_tile` (on the tile's own `InkWell` inside the fork's `TencentCloudChatUserProfileChatButton`). Do NOT tap the outer group key `UiKeys.friendProfileSendMessageButton` (`friend_profile_send_message_button`) — it is a `KeyedSubtree` (NO onTap of its own, lib/ui/home_page_bootstrap.dart) wrapping the WHOLE [Send Message, Voice Call, Video Call] row, and a `marionette.tap({key})` lands on the CENTER of the keyed widget = the MIDDLE tile = **Voice Call**, NOT Send (geometry asserted by the L1 gate). The Send tile's handler is the upstream `onNavigateToChat`, which routes via toxee's `_onTapContactItem` (home_page.dart:947-951; the Send-Message-vs-other discriminator is the contact-profile-route flag, home_page.dart:1665-1667).
4. Wait for the message panel to mount (poll `fmt_semantic_snapshot` ≤10s for the header with `<nickF>`).

## Assertions
- A1 (pre-tap, control): `l3_dump_state.currentConversation == null` (no chat open); baseline `get_runtime_errors` empty.
- A2 (primary, post-tap): the C2C conversation for F opens — `fmt_capture_ui_snapshot` shows a `TencentCloudChatMessageHeader` (tencent_cloud_chat_message_header.dart:7) titled `<nickF>`; AND `l3_dump_state.currentConversation.conversationID == "c2c_<toxF>"` with `showName == <nickF>`.
- A3 (composer present): the chat composer `UiKeys.chatInputTextField` (`chat_input_text_field`, attached at home_page_bootstrap.dart:629) is present in the mounted panel — confirms the message panel (not a blank route) mounted.
- A4: `official.get_runtime_errors({})` empty vs the Step-1 baseline; no `FATAL`/`terminate called`.

## Notes
- L3-pin reason: the tile→`onNavigateToChat`→`_onTapContactItem` navigation mounts the real UIKit message panel under the engine; the routing logic is L1/L2-promotable behind a constructor seam, but the panel-mount observable is L3 today.
- Key verified: `friend_profile_send_message_button` @ lib/ui/home_page_bootstrap.dart:1125 (toxee-owned `KeyedSubtree(key: UiKeys.friendProfileSendMessageButton, ...)`). Defined at ui_keys.dart:297.
- The key wraps the WHOLE [Send Message, Voice Call, Video Call] tile group (ui_keys.dart:291-299 comment) — voice/video tiles share this outer key, and the group key itself has NO onTap. A center key-tap on `friend_profile_send_message_button` lands on the MIDDLE tile = **Voice Call**, so do NOT key-tap the group to drive Send. The per-tile fix has landed: tap `friend_profile_send_message_tile` (fork `TencentCloudChatUserProfileChatButton`, applied to the tile's own `InkWell`) to dispatch `onNavigateToChat`; voice/video carry `friend_profile_voice_call_tile` / `friend_profile_video_call_tile`. The call buttons have their OWN keys (`UiKeys.chatCallVoiceButton` / `chatCallVideoButton`) and are covered by the call scenarios (S65/S67/…); do NOT assert call behavior here.
- Sibling distinction: S11 (open conversation from the Chats list) reaches the same panel via the conversation-list row; S115 reaches it via the friend-profile Send-Message tile. Same panel, different entry point.
- Mobile parity: the per-tile keys (`friend_profile_send_message_tile` / voice / video) live in the SHARED fork `TencentCloudChatUserProfileChatButton` (no platform split), and the outer `friend_profile_send_message_button` wrapper sits at the toxee builder boundary — iOS/Android render the same tiles and route through the same `onNavigateToChat`/`_onTapContactItem`, so this scenario covers mobile via the same anchors.
