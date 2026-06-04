# S115 — Friend profile: "Send Message" tile → opens conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1(F, echo-peer seed)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned for the real-tap navigation (the tile's `onNavigateToChat` → toxee `_onTapContactItem` route mounts the real message panel under the engine); the navigation-routing assertion is an L1/L2 candidate behind a seam once the contact-profile route is constructor-injectable.
**Status**: covered (keying GAP: `friendProfileSendMessageButton` wraps the whole [Send, Voice, Video] tile row; a center key-tap hits Voice, so Send must be tapped by leftmost-position/label — a per-tile `friend_profile_send_message_tile` key is owed). Pure-UI navigation, L3 / L1 candidate; NOT a runnable gate. NOT "covered (executable)" — there is no runnable UI gate.

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
3. Drive the SEND tile specifically. `UiKeys.friendProfileSendMessageButton` (`friend_profile_send_message_button`) is a `KeyedSubtree` (NO onTap of its own) at lib/ui/home_page_bootstrap.dart:1124-1125 that wraps the WHOLE upstream `TencentCloudChatUserProfileChatButton` — a ROW of three tiles [Send Message, Voice Call, Video Call]. A `marionette.tap({key})` lands on the CENTER of the keyed widget, and the center of a 3-tile row is the MIDDLE tile = **Voice Call**, NOT Send. So do NOT tap the group key here. Instead tap the LEFTMOST tile by semantic ref / its "Send Message" label — the Send tile has NO dedicated key of its own. The Send tile's handler is the upstream `onNavigateToChat`, which routes via toxee's `_onTapContactItem` (home_page.dart:947-951; the Send-Message-vs-other discriminator is the contact-profile-route flag, home_page.dart:1665-1667).
4. Wait for the message panel to mount (poll `fmt_semantic_snapshot` ≤10s for the header with `<nickF>`).

## Assertions
- A1 (pre-tap, control): `l3_dump_state.currentConversation == null` (no chat open); baseline `get_runtime_errors` empty.
- A2 (primary, post-tap): the C2C conversation for F opens — `fmt_capture_ui_snapshot` shows a `TencentCloudChatMessageHeader` (tencent_cloud_chat_message_header.dart:7) titled `<nickF>`; AND `l3_dump_state.currentConversation.conversationID == "c2c_<toxF>"` with `showName == <nickF>`.
- A3 (composer present): the chat composer `UiKeys.chatInputTextField` (`chat_input_text_field`, attached at home_page_bootstrap.dart:629) is present in the mounted panel — confirms the message panel (not a blank route) mounted.
- A4: `official.get_runtime_errors({})` empty vs the Step-1 baseline; no `FATAL`/`terminate called`.

## Notes
- L3-pin reason: the tile→`onNavigateToChat`→`_onTapContactItem` navigation mounts the real UIKit message panel under the engine; the routing logic is L1/L2-promotable behind a constructor seam, but the panel-mount observable is L3 today.
- Key verified: `friend_profile_send_message_button` @ lib/ui/home_page_bootstrap.dart:1125 (toxee-owned `KeyedSubtree(key: UiKeys.friendProfileSendMessageButton, ...)`). Defined at ui_keys.dart:297.
- The key wraps the WHOLE [Send Message, Voice Call, Video Call] tile group (ui_keys.dart:291-299 comment) — voice/video tiles share this outer key, and the group key itself has NO onTap. A center key-tap on `friend_profile_send_message_button` lands on the MIDDLE tile = **Voice Call**, so do NOT key-tap the group to drive Send. Tap the LEFTMOST tile by position/"Send Message" label to dispatch `onNavigateToChat`. The real fix is a per-tile `friend_profile_send_message_tile` key (owed). The call buttons have their OWN keys (`UiKeys.chatCallVoiceButton` / `chatCallVideoButton`) and are covered by the call scenarios (S65/S67/…); do NOT assert call behavior here.
- Sibling distinction: S11 (open conversation from the Chats list) reaches the same panel via the conversation-list row; S115 reaches it via the friend-profile Send-Message tile. Same panel, different entry point.
- Mobile parity: `friend_profile_send_message_button` wraps the SHARED UIKit `TencentCloudChatUserProfileChatButton` at the toxee builder boundary (no platform split) — iOS/Android render the same tile group and route through the same `_onTapContactItem`, so this scenario covers mobile via the same anchor.
