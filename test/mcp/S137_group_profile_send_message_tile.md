# S137 — Group: the profile Send Message tile returns to chat

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once the custom group-profile chat button is directly targetable; adjacent single-chat sibling is S115
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` drives the toxee override chat button by key and asserts `onNavigateToChat(groupID)` fires.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- `TencentCloudChatGroupProfile` is open for `<gidG>`.
- The toxee group-profile chat button renders the single Send Message tile.

## UI Driver
1. From the opened group profile, tap `UiKeys.groupProfileSendMessageButton` (`group_profile_send_message_button`).
2. Wait for the app to navigate back into the active group chat.

## Assertions
- Navigation returns to the group conversation for `<gidG>`.
- The message pane is re-mounted and ready for input.
- No runtime errors appear vs baseline.

## Notes
- Unlike the friend profile, toxee's group profile renders only a single Send Message tile here.
- This case is distinct from simply opening the profile; it proves the return-to-chat affordance.
- Key status: the toxee override now exposes a stable `group_profile_send_message_button` anchor, so this case no longer depends on localized button text.
