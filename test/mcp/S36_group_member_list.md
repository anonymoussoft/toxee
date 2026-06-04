# S36 — View group member list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gid w/ N≥3 members] history=non-empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because Platform-path `getGroupMemberList` FFI and `_enrichAvatars` cross-fill need a real session
**Status**: covered

## Precondition
- One signed-in account A with one joined group containing N≥3 members (variants: A=owner, A=member, empty-history).
- `account_data/<toxA>/messages/group_<gid>.json` has at least one message from each non-self member (fallback discovery needs sender PKs).
- `Prefs.group_owner_<gid>` populated so the owner row appears even without history from owner.
- `MCP_BINDING=marionette` (header avatar tap has no label).

## Driver
1. Tap conversation row for the group by `UiKeys.groupListTile("<gid>")` (`group_list_tile:<gid>`). Semantic ref remains the fallback for runtime-discovered groups.
2. Tap chat panel header — pushes `TencentCloudChatGroupProfile`.
3. Tap the members entry by `UiKeys.groupProfileMembersEntry` (`group_profile_members_entry`) inside the group profile.
4. Wait for `GroupMemberListWrapper` to mount + shimmer to clear (≤5s).
5. Tap a non-self row — `onManageMember` shows `CupertinoActionSheet`.
6. Tap `Info` action — opens `TencentCloudChatGroupMemberInfo` (desktop: showCustomDialog; phone: pushed route).

## Assertions
- Member list page mounts: Scaffold + AppBar + AzListView with N rows.
- Row count equals N: cross-check via `fmt_evaluate_dart_expression` on `loadGroupMemberList(groupID:, loadGroupAdminAndOwnerOnly: false).length`.
- Each row label contains nickname (or userID fallback) + role text (`tL10n.groupOwner` / `tL10n.admin` / `tL10n.groupMember`).
- Owner badge renders on owner row (Container at UIKit fork lines 579-595); admin badge on admin row (lines 596-612).
- Self row present and has **no trailing chevron** (UIKit fork line 646 guards with `if (!isSelf())`).
- After Step 6: widget tree contains `TencentCloudChatGroupMemberInfo` with the tapped member's name.
- Log markers: `[Tim2ToxSdkPlatform]` Platform-path call; `[GroupMemberListWrapper]` init + history load.
- Negative grep: `[GroupMemberListWrapper] member fetch failed`, `getGroupMemberList failed`, `ToxManager not initialized` must not appear.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- AZ list sorts alphabetically by uppercase first letter of `nameCard ?? nickName ?? userID`; owner is NOT pinned to top (the `adminAndOwner` slot at UIKit fork line 219 is a no-op).
- Shimmer shows 10 rows during load; wait for clear before snapshotting count.
- `_enrichAvatars` only fills when member's own field is empty (lines 50-57) — intentional, friends-in-group display contact list nickname/face when their own group nameCard is empty.
- Empty-history variant gates the FFI happy path; pure-fallback derivation needs message-history sender PKs + `group_owner_<gid>` pref.
- Action sheet on desktop also has secondary-tap context menu — use primary tap for Step 5 to get the action sheet.
- Phone variant (push route instead of side panel) deferred; Step 4-9 reframe.
