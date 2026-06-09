# S170 — Conference: profile content shows the resolved conference ID

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC]`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once profile-content assertions are runner-covered; adjacent sibling is S140
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` asserts the toxee profile content renders a stable `Group ID:` text surface under the conference branch as well.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference `<gidC>` profile is open.

## UI Driver
1. Read `UiKeys.groupProfileIdText` (`group_profile_id_text`) in the profile content area under the conference name.
2. Wait for any deferred conference-id resolution to settle.

## Assertions
- The profile shows `Group ID: ...` using the resolved conference/chat identifier when available.
- The displayed identifier remains selectable text in the profile content.
- No runtime errors appear vs baseline.

## Notes
- The profile content code contains explicit retry logic for conference ID resolution.
- This makes the conference version slightly more interesting than the plain group case.
- Key status: the shared toxee content override now exposes a stable `group_profile_id_text` anchor for this `SelectableText`.
