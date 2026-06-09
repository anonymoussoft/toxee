# S166 — Conference: open the profile from the active chat header

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] history=seeded`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once header tapping for conference chats is stabilized; adjacent siblings are S136 and S121-S123
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_profile_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference `<gidC>` is already open in the chat pane.
- The conference profile route is reachable by tapping the chat header.

## UI Driver
1. Tap the active conference chat header/avatar area.
2. Wait for `TencentCloudChatGroupProfile` to mount.

## Assertions
- The conference profile route opens from the real chat header.
- The mounted profile exposes the toxee override surface for avatar, content, member entry, and destructive rows.
- No runtime errors appear vs baseline.

## Notes
- Conference profile rendering reuses the same toxee override layer as group profile rendering.
- The current runner blocker is still the missing dedicated header key.
