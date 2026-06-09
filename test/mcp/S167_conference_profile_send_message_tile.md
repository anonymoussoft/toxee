# S167 — Conference: the profile Send Message tile returns to chat

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once the custom profile chat button is directly targetable; adjacent sibling is S137
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` drives the toxee override chat button by key and asserts `onNavigateToChat(groupID)` fires for a conference/groupID payload.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- `TencentCloudChatGroupProfile` is open for `<gidC>`.
- The toxee group-profile chat button renders the single Send Message tile.

## UI Driver
1. From the opened conference profile, tap `UiKeys.groupProfileSendMessageButton` (`group_profile_send_message_button`).
2. Wait for the app to navigate back into the active conference chat.

## Assertions
- Navigation returns to the conference conversation for `<gidC>`.
- The message pane is re-mounted and ready for input.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S137.
- The chat button is conference-safe because toxee's override only exposes send-message, not call actions.
- Key status: the shared toxee override now exposes a stable `group_profile_send_message_button` anchor here too.
