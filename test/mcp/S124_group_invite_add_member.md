# S124 — Group invite: Add-member button → picker → confirm (two processes)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=1(A↔B pre-paired) groups=A-hosts` (`paired_for_e2e`)
**Harness mode**: peerHarness=none (two toxee processes, not echo peer)
**Promotion target**: n/a — L3-pinned on two real toxees + live invite delivery / accept timing over the DHT. The invite SEND is live from UIKit; the residual is native NGC delivery / propagation, not a no-op stub.
**Status**: covered (invite-send + delivery FIXED in Dart; the friend-PICKER selection is mostly text/semantic with no per-row key — note the gap). Gate `run_fixture_c_group_invite.sh`. Two-process NGC reliability is the native residual (S81). Shared with S81/S47.

> Real-UI sibling of S81. S81 frames the invite from the inviteUserToGroup data path; S124 walks the keyed UI: in a group, tap the add-member button → the friend picker opens → select friend B → tap confirm, which drives `inviteUserToGroup(groupID, [toxB])`. The native-delivery residual S81 records applies verbatim.

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`.
- Two toxee instances launched by `tool/mcp_test/launch_fixture_c_pair.sh` (restore `paired_for_e2e`); A/B isolated by `TOXEE_APP_SUPPORT_DIR`, `TOXEE_SHARED_PREFS_PREFIX`, `TOXEE_TCCF_GLOBAL_SUBDIR`. Same-host instances never bootstrap to each other, so the driver wires full-mesh local bootstrap (`l3_dht_info` + `l3_add_bootstrap_node`, already wired in the 3 group drivers).
- A and B already mutual friends (Tox group invite requires an existing friendship); both reach Online before driving (poll `<nick>\nOnline` ≤60s per side).
- A hosts a group `<gidG>` with B invitable into it (create on A first; `checkCanAddMember()` requires `approveOpt != V2TIM_GROUP_ADD_FORBID`, `tencent_cloud_chat_group_profile_body.dart:1518-1523`). For NGC groups the invite goes via `tox_group_invite_friend`; for conferences via `tox_conference_invite` — branch picked in C++ (`V2TIMGroupManagerImpl.cpp:2790-2848`).
- Drive instance A (inviter); instance B (invitee) stays alive and is polled for the inbound invite + auto-join. B's auto-accept-group Pref `acct_auto_accept_group_invites_<toxB_prefix16>` decides manual-vs-auto (sibling S47); `run_fixture_c_group_invite.sh` turns it ON (B auto-joins, no manual accept).
- `MCP_BINDING=marionette` per instance.

## Executable Driver

```bash
tool/mcp_test/run_fixture_c_group_invite.sh
```

Restores `paired_for_e2e`, boots both accounts, B turns `autoAcceptGroupInvites` ON, A creates a group and INVITES friend B (S81 invite-send via `l3_invite_to_group`), and B auto-joins (S47 auto-accept). This is the invite DATA path gate (with the native NGC delivery/propagation residual S81 records). It drives the invite through `l3_invite_to_group`, NOT through the add-member UI; the keyed picker tap below is the marionette real-UI upgrade on top of this proven invite path.

## UI Driver
1. On A: poll `<nick>\nOnline` ≤60s; baseline `official.get_runtime_errors({})`. Confirm `<gidG>` in A's `l3_dump_state.knownGroups`.
2. On A: open the group → group profile (tap the group row `UiKeys.groupListTile("<gidG>")` → tap the header to push `TencentCloudChatGroupProfile`).
3. On A: tap `UiKeys.groupAddMemberButton` (`group_add_member_button`) — the keyed `Container` wrapping the `GestureDetector.onTap: addGroupMembers` (`third_party/chat-uikit-flutter/tencent_cloud_chat_message/lib/group_profile_widgets/tencent_cloud_chat_group_profile_body.dart:1557`). `addGroupMembers` (`:1372`) navigates to `TencentCloudChatGroupAddMember` (the friend picker).
4. On A: select friend B from the picker. **Gap**: the picker rows (`TencentCloudChatGroupProfileAddMemberList`, `tencent_cloud_chat_group_add_member.dart:104`) are an AZ list with NO per-row UiKey — select by semantic ref / B's nickname label (the S26/S61 text-tap idiom). The selection updates `selectedContacts` via `onChanged` (`:57-59`).
5. On A: tap `UiKeys.groupMemberInviteConfirmButton` (`group_member_invite_confirm_button`) — the AppBar confirm TextButton (`tencent_cloud_chat_group_add_member.dart:81`). Fires `submitAdd` (`:31`) → `contactPresenter.inviteUserToGroup(groupID, userList:[toxB])` (`contact_presenter.dart:173`) → SDK group manager → native_im → C++ `InviteUserToGroup`.
6. On B (auto-accept leg): poll B's `l3_dump_state.knownGroups` / conversation list ≤60s for `<gidG>` appearing after auto-join.

## Assertions
- A1 (send, log on A): `[InviteUserToGroup] ENTRY groupID=<gidG> userList.Size()=1` (`V2TIMGroupManagerImpl.cpp:2552`, unconditional). For the conference branch the marker is `using tox_conference_invite` (`:2813-2814`). (There is no runtime `using tox_group_invite_friend` log — that string is only a CODE COMMENT at `:2790`, not a logged line; the NGC branch is the default non-conference path.) These are the S81 A1 markers.
- A2 (send success, log on A): the Tox call returns OK (`TOX_ERR_GROUP_INVITE_FRIEND_OK` / `TOX_ERR_CONFERENCE_INVITE_OK` path); NO `INVITE_FAIL` / `NO_CONNECTION` / `FRIEND_NOT_FOUND` error branch. (S81 A2.)
- A3 (receive + auto-accept, log on B): inbound invite + auto-accept logged under `[GroupInvite]` markers — `[GroupInvite] ========== Received group invite ==========` (`V2TIMManagerImpl.cpp:535`), `[GroupInvite] Auto-accept group invites setting: true` (`:571-572`), and the `OnMemberInvited` notify (`:591`/`:619`). (S81 A3, auto-accept variant.)
- A4 (primary, on B): B **RECEIVES an inbound group MESSAGE** (`isSelf==false`, exact nonce text `S47 invite <nonce>`) under a candidate group key — this is the driver's actual auto-join proof. B's Dart-side `knownGroups` may NOT contain `<gidG>` (the protocol-level auto-accept does not surface in Dart `knownGroups`; `drive_fixture_c_group_invite.dart:16-23,177`). The candidate group keys are recomputed from `knownGroups ∪ type==2 conversationIds` and each is scanned via `l3_dump_state{conversationId:'group_'+candidate}.messages` for the inbound nonce. So `conversationIds`/`type==2` is the candidate-key SOURCE, NOT a hard "`knownGroups` contains `<gidG>`" assert. (S81 A4.)
- A5 (bidirectional, on A): B shows up in A's group member list within 30-60s of B joining (S81 A5).
- A6: `official.get_runtime_errors({})` empty vs Step 1 baseline on both sessions (S81 A6).

## Notes
- **Native residual (explicit)**: the invite no longer dies in a local-only stub — `Tim2ToxSdkPlatform.inviteUserToGroup` delegates into native_im → `DartInviteUserToGroup` → C++ → `tox_group_invite_friend`/`tox_conference_invite` (S81 note 1). The residual shared with S47 is native NGC delivery / post-accept propagation timing between two fresh instances (invite races + when the accepted group becomes visible in Dart `knownGroups`) — same ~40% per-attempt NGC discovery that makes `run_fixture_c_member_list.sh` retry fresh sessions.
- **Picker key gap (honest)**: the add-member picker rows have NO per-row UiKey; only the ENTRY (`group_add_member_button`, body:1557) and the CONFIRM (`group_member_invite_confirm_button`, add_member:81) are keyed. Step 4 must select by semantic ref / nickname. This is the documented gap, not a covered key.
- Keys verified: `groupAddMemberButton` @ `tencent_cloud_chat_group_profile_body.dart:1557`; `groupMemberInviteConfirmButton` @ `tencent_cloud_chat_group_add_member.dart:81` (both defined `ui_keys.dart:263-266`). Invite wire: `add_member:36` → `contact_presenter.dart:173`.
- Sibling distinction: S81 = invite from the data-path framing (same `run_fixture_c_group_invite.sh` gate + native residual); S124 = the keyed add-member UI walk of the SAME invite; S47 = the auto-accept-toggle half (shares the gate). The invite-send UI is pure upstream UIKit — `lib/ui/group/group_builder_override.dart` overrides avatar/chat/content/delete/member builders only, NOT add-member (S81 note 3).
- Mobile parity: the add-member entry + picker + confirm are upstream UIKit widgets shared across platforms (the fork is user-owned but unmodified for invite); the keys cover mobile. NGC invite delivery is platform-agnostic native.
