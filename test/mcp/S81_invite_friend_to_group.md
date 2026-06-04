# S81 — Invite a friend to a group (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(A↔B pre-paired) groups=A-hosts` (`paired_for_e2e`)
**Harness mode**: peerHarness=none (two toxee processes, not echo peer)
**Promotion target**: n/a — still L3-pinned on two real toxees plus live invite delivery / accept timing over the DHT. The send path itself is now live from UIKit; the remaining uncertainty is native delivery / propagation behavior, not a no-op stub.
**Status**: invite-send + delivery FIXED (Dart) — the UIKit/Platform invite was a no-op; now delegates to native_im → C++ `tox_group_invite_friend`. Live-proven: the invitee receives and auto-accepts the invite (`tox_group_invite_accept` err=0). Gate `run_fixture_c_group_invite.sh`. Two-process reliability (NGC delivery timing) is the native residual. Shared with S47.

## Precondition
- Two toxee instances in separate macOS Containers (distinct `CFBundleIdentifier`) so `SharedPreferences` don't clobber; both plaintext, `autoLogin=true`, `MCP_BINDING=marionette`.
- A and B already mutual friends (Tox group/conference invite requires an existing friendship); both reach Online before driving (poll `<nick>\nOnline` ≤60s per side).
- A hosts a group with B invitable into it (run S32 on A first). For NGC groups invite goes via `tox_group_invite_friend`; for conferences via `tox_conference_invite` — branch picked in C++ (`V2TIMGroupManagerImpl.cpp:2790-2848`).
- Drive instance A (inviter) for the steps; instance B (invitee) stays alive and is polled for the inbound invite. B's auto-accept-group Pref decides manual-vs-auto (sibling S47): set `acct_auto_accept_group_invites_<toxB_prefix16>=false` to force the manual-accept leg.

## Driver
1. On A: open the group → group profile → tap `UiKeys.groupAddMemberButton` (`group_add_member_button`) to enter the add-member flow.
2. On A: select friend B from the picker and confirm via `UiKeys.groupMemberInviteConfirmButton` (`group_member_invite_confirm_button`); this drives `inviteUserToGroup(groupID, [toxB])` (`tencent_cloud_chat_group_add_member.dart:32` → presenter `tencent_cloud_chat_contact/lib/model/contact_presenter.dart:173`).
3. On B (manual leg): poll conversation list / New Contacts ≤30s for the inbound group-invite notification; tap accept via `UiKeys.groupInviteAcceptButton(groupId)` (`group_invite_accept_button:<gid>`).
4. On B: confirm the group row appears in B's conversation list after accept.

## Assertions
- A1 (send, log on A): `[InviteUserToGroup] ENTRY groupID=<gid> userList.Size()=1` → `InviteUserToGroup: inviting 1 users to group <gid>` (`V2TIMGroupManagerImpl.cpp:2549,2594`) → branch log `using tox_group_invite_friend` or `using tox_conference_invite` (`V2TIMGroupManagerImpl.cpp:2790-2848`).
- A2 (send success, log on A): the Tox call returns OK — `TOX_ERR_GROUP_INVITE_FRIEND_OK` / `TOX_ERR_CONFERENCE_INVITE_OK` path; NO `INVITE_FAIL`/`NO_CONNECTION`/`FRIEND_NOT_FOUND` error branch (`V2TIMGroupManagerImpl.cpp:2839-2848`).
- A3 (receive, log on B): inbound `[GroupInvite]` handling; for manual leg `[GroupInvite] Auto-accept is disabled, storing as pending invite` (`V2TIMManagerImpl.cpp`), then on accept `tox_group_invite_accept` (`V2TIMManagerImpl.cpp:628,635`).
- A4 (primary, on B): group row appears in B's conversation list after manual accept; `defaults read com.toxee.b.app flutter.groups` contains `<gid>`.
- A5 (bidirectional, on A): B shows up in A's group member list within 30-60s of B accepting.
- A6: `official.get_runtime_errors({})` empty vs Step 0 baseline on both sessions.

## Notes
- `Tim2ToxSdkPlatform.inviteUserToGroup` now delegates back into the native_im / binary-replacement path (`TIMGroupManager.instance.inviteUserToGroup(...)` in `third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart`), so the UIKit-reachable invite no longer dies in a local-only stub. The relevant wire path is now UIKit presenter → SDK group manager → native_im → `DartInviteUserToGroup` → C++ `V2TIMGroupManagerImpl::InviteUserToGroup` → `tox_group_invite_friend` / `tox_conference_invite`.
- The residual issue shared with S47 is no longer "invite never left the wire"; it is native NGC reliability and post-accept propagation timing between two fresh instances (invite delivery races + when the accepted group becomes visible in Dart-side `knownGroups`).
- No toxee-side invite UI affordance: `lib/ui/group/group_builder_override.dart` overrides avatar/chat/content/delete builders only — invite-send is pure upstream UIKit (`TencentCloudChatGroupAddMember`).
- Key status: `group_add_member_button`, `group_member_invite_confirm_button`, and `group_invite_accept_button:<gid>` are available.
