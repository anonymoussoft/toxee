# S121 — Group profile: Members entry → member-list panel (real tap)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded`
**Harness mode**: peerHarness=none (single-instance group create/open is hermetic; full member content with a remote peer is Fixture C — see S36)
**Promotion target**: L1 WidgetTester for the entry-tap → member-panel mount + navigation; live multi-member content is L3-pinned (Fixture C `run_fixture_c_member_list.sh`).
**Status**: entry surface covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` renders the toxee keyed wrapper with a minimal current-user fixture and asserts `group_profile_members_entry` is present. Full panel mount + SELF-row verification remain outside executable widget coverage.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

> Real-UI sibling of S36. S36 drives the SDK→C++ `GetGroupMemberList` path with a joined remote peer B over two processes. S121 is the single-instance real-tap of the keyed members ENTRY: open a group → group profile → tap the members entry → the member-list panel mounts and shows SELF (the only member when no peer has joined).

## Precondition
- Debug macOS app built with the L3 surface:
  `flutter build macos --debug --dart-define=MCP_BINDING=marionette --dart-define=TOXEE_L3_TEST=true`; launched `MCP_BINDING=marionette ./run_toxee.sh`.
- One signed-in account A; exactly one joined group `<gidG>` with non-empty `Prefs.group_name_<gidG>`. Hermetic seed: `l3_create_group {name:'S121 members'}` returns the local `<gidG>` and adds it to `ffi.knownGroups` (verify `l3_dump_state.knownGroups` contains `<gidG>`, `l3_debug_tools.dart:3672`); `l3_dump_state.conversationIds` contains `group_<gidG>` (`:3659`).
- Account A logged in, plaintext, sidebar Online (poll `<nick>\nOnline` ≤60s).
- `MCP_BINDING=marionette` — the chat-header avatar tap that opens the group profile has no text label.
- Single instance, no peer joined: the member set is `{self}` only — a real peer member needs Fixture C (S36).

## UI Driver
1. `marionette.tap(UiKeys.sidebarChats)` (`sidebar_chats_tab`); baseline `official.get_runtime_errors({})`.
2. Tap the group's conversation row by `UiKeys.groupListTile("<gidG>")` (`group_list_tile:<gidG>`, attached at the toxee override boundary, `ui_keys.dart:157`). Semantic-ref / label match is the runtime-discovery fallback (same as S35/S36 step 1).
3. Tap the chat panel header (avatar/title) — pushes `TencentCloudChatGroupProfile`. No key on the header; tap by ref (the S35/S36 idiom).
4. Tap the members entry by `UiKeys.groupProfileMembersEntry` (`group_profile_members_entry`) — this is the toxee `KeyedSubtree` wrapping `TencentCloudChatGroupProfileGroupMember` (`lib/ui/group/group_builder_override.dart:65`). It opens the member-list panel (`GroupMemberListWrapper` / `TencentCloudChatGroupProfileGroupMember`).
5. Wait for the panel to mount + shimmer to clear (≤5s); `fmt_semantic_snapshot`.

## Assertions
- A1 (clean baseline): Step 1 — `official.get_runtime_errors({})` empty; `l3_dump_state.knownGroups` contains `<gidG>` and `conversationIds` contains `group_<gidG>`.
- A2 (panel mounts, primary): after Step 4 — the widget tree contains the member-list panel (Scaffold/AppBar + the AzListView the member rows live in); snapshot shows at least one member row. This is the L1-promotable assertion (entry-tap → panel mount).
- A3 (self present): the panel shows A's own row — exactly one self entry whose label is A's nickname / userID; SELF has **no trailing chevron** (UIKit fork guards trailing with `if (!isSelf())`, the same line S36 cites). With no peer joined this is the ONLY row.
- A4 (no peer — honest scope): the panel does NOT show a second non-self member (none has joined this single instance). A real joined peer is asserted only by S36's `run_fixture_c_member_list.sh`; do NOT assert peer rows here.
- A5: `official.get_runtime_errors({})` matches the Step-1 baseline; negative grep (member-list path): `[GroupMemberListWrapper] member fetch failed`, `getGroupMemberList failed`, `ToxManager not initialized` MUST NOT appear (the S36 negative-grep set).

## Notes
- L3-pin reason: the marionette header-tap → profile-push → entry-tap gesture chain is not yet a runnable gate; the single-instance member READ is shimmer-then-self only. Multi-member content with a live peer is intrinsically two-process (a single instance can't observe a joined remote member — coverage map line 645-648), so that half stays in `run_fixture_c_member_list.sh` (which retries ~4 fresh paired sessions at ~40% NGC-discovery per attempt).
- Key verified: `groupProfileMembersEntry` @ `lib/ui/group/group_builder_override.dart:65` (defined `ui_keys.dart:167`), wrapping `TencentCloudChatGroupProfileGroupMember`.
- Sibling distinction: S36 = two-process member-list READ with peer B (`run_fixture_c_member_list.sh`); S121 = single-instance real-tap of the members ENTRY (panel mount + self). S122/S123 are the OTHER two keyed group-profile rows (clear-history / leave).
- Mobile parity: the members entry is wired in the SHARED toxee builder override (`lib/ui/group/group_builder_override.dart`), so the keyed entry covers mobile; only the desktop side-panel vs phone push-route presentation differs (S36 note 7).
- No executable single-instance gate for the full member panel itself yet: the closest data-half is S36's two-process gate. The current widget-level coverage is intentionally narrower and only claims the keyed entry surface.
