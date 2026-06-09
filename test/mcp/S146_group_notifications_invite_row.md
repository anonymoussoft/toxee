# S146 — Group: group-notifications tab shows a pending invite row

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A inviter,B invitee in separate sandboxes) current(B)=B1 autoLogin=on network=online friends=1 pendingGroupInvite=present`
**Harness mode**: peerHarness=none (two toxee processes; pending invite required)
**Promotion target**: L3 candidate once real-ui group-notifications runners exist; adjacent siblings are S106, S110, and S81
**Status**: N/A for toxee (2026-06-08, codex-reviewed) — intentional product scope, not a blocked test. The Tox backend has NO group-application concept: the Contacts UI intentionally OMITS the "Group notifications" tab (`tencent_cloud_chat_contact.dart`, desktop + mobile branches — removed in toxee), and Tim2Tox stubs the backend (`tim2tox_sdk_platform.dart` `getGroupApplicationList()` returns `[]`, `acceptGroupApplication()` is a no-op). Group invites are delivered + accepted over the native `onGroupInvited`/auto-accept path, never surfaced as an acceptable "application". There is no invite-row to render, so this scenario does not apply. See [[real_ui_group_message_fresh_nontest]].

## Precondition
- B has an unresolved pending group invite for `<gidG>`.
- The Contacts shell is available on B.

## UI Driver
1. Open Contacts.
2. Tap `UiKeys.contactGroupNotificationsTab`.
3. Inspect the rendered invite list.

## Assertions
- A pending invite row for `<gidG>` is visible in the group-notifications list.
- The row resolves to the inbound invite state rather than an empty-state panel.
- No runtime errors appear vs baseline.

## Notes
- This is the group-notification-list sibling around the same invite family covered by S81/S124/S47.
- It focuses on list presence, not accept/join completion.
