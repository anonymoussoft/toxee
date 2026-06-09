# S140 — Group: profile content shows the resolved group ID

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG]`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once profile-content assertions are runner-covered; adjacent siblings are S32 and S136
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` asserts the toxee profile content renders a stable `Group ID:` text surface and the expected ID payload.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- Group `<gidG>` profile is open.

## UI Driver
1. Read `UiKeys.groupProfileIdText` (`group_profile_id_text`) in the profile content area under the group name.
2. Wait for any deferred chat-id resolution to settle if applicable.

## Assertions
- The profile shows `Group ID: ...` using either the resolved chat ID or the backing group ID.
- The displayed identifier remains selectable text in the profile content.
- No runtime errors appear vs baseline.

## Notes
- This case intentionally targets the existing `SelectableText` identifier surface rather than a dedicated copy button.
- It is especially relevant for groups whose chat ID may resolve asynchronously after mount.
- Key status: the toxee content override now exposes a stable `group_profile_id_text` anchor for this `SelectableText`.
