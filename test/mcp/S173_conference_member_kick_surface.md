# S173 — Conference: kick-action is NOT offered for conference members (no roles)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC]`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once real-ui two-process moderation driving is added; adjacent siblings are S143 and S37
**Status**: covered (truthful NEGATIVE) at the widget layer — real-UI L1 gate (`test/ui/conference/conference_members_real_ui_test.dart`). A legacy conference is `GroupType.AVChatRoom`, for which `canDeleteMember()` short-circuits to false (`tencent_cloud_chat_group_member_list.dart:341-343`) — conferences have no roles/moderation (see S156: "no roles"), so the kick action is NOT surfaced. The spec's original "kick appears" premise was wrong for the conference branch; the gate asserts the kick is ABSENT, with a Work-group control proving the absence is conference-specific.
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- A opens a conference member's manage sheet from the member list.
- The same member/role setup on a Work group is available as a control.

## UI Driver
1. Open a conference (`AVChatRoom`) member's manage action sheet (tap the member row).
2. Inspect the sheet for `UiKeys.groupMemberActionKickButton`.
3. Repeat with a Work group of the same owner/member roles (control).

## Assertions
- For a conference (`AVChatRoom`) member the manage sheet opens (Info action present) but offers NO kick action — `canDeleteMember()` is false for AVChatRoom because conferences have no roles/moderation.
- A Work group with the same owner/member roles DOES surface the kick action — proving the conference absence is the AVChatRoom gate, not a setup gap.
- No runtime errors appear vs baseline.

## Notes
- This is the conference counterpart of S143, but inverted: where an NGC group (Work) surfaces kick, a legacy conference does not.
- Whether a kick succeeds for groups is a separate two-process moderation scenario (S37); for conferences the action does not exist in the UI at all.
