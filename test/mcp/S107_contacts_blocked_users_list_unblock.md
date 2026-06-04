# S107 — Contacts: Blocked-Users tab listing + unblock

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1 (blocklist seeded with F)`
**Harness mode**: peerHarness=none — blocklist is pure Prefs + listener notify (S29 establishes this); F does NOT need to be online or running to appear in the Blocked-Users tab.
**Promotion target**: L3-pinned only loosely — the listing surface itself is hermetic, but the unblock control round-trips through Tim2Tox `deleteFromBlackList` + `SharedPreferencesAdapter`, so the data-half belongs at L2/L1 with `l3_set_blocked`. This scenario is the **UI-surface view** of S29's data-half: S29 toggles via the user-profile `blackUser` switch and asserts Prefs; S107 asserts the Blocked-Users TAB renders the blocked peer as a row and that unblocking from there clears it.
**Status**: spec-only for the UI-surface angle. Data-half is **covered (executable)** by S29's gate (`tool/mcp_test/run_fixture_c_block.sh` + `tool/mcp_test/scenarios/l3_block_toggle.json`); this scenario does not add a new runnable gate — it pins the list-rendering + unblock-entry UI that S29's data-half does not exercise.

## Precondition
- Account A logged in, plaintext, sidebar Online (poll 60s)
- `Prefs.local_friends_<toxA>` contains `<toxF>`; F is a friend (the blocked peer must already be a friend — S29-A11 keeps friendship intact across block)
- `Prefs.black_list_<toxA>` (LEGACY full-toxId key, NOT 16-char prefix — `shared_prefs_adapter.dart:40-45`) contains `<toxF>` BEFORE launch, so the Blocked-Users tab has a row to render. Seed via S29 step 2, or pre-flight `l3_set_blocked {userId:<toxF>, blocked:true}` (`l3_debug_tools.dart:1496`), then verify `l3_dump_state.blockedUsers` contains `<toxF>` (`l3_debug_tools.dart:3598`).
- `l3_dump_state.blockedUsers[]` includes `<toxF>` at start (the gate the listing is asserted against)

## Executable Driver

```bash
tool/mcp_test/run_fixture_c_block.sh
```

This is **S29's** cross-process gate (restores `paired_for_e2e`, A blocks B, asserts B's text is dropped before history, A unblocks B, asserts a second text lands). It proves the block/unblock **data-path** end-to-end but drives it via `l3_set_blocked` on the FfiChatService — it never opens the Blocked-Users TAB or taps a row. S107 is the UI-control complement: it asserts the tab renders the blocked peer and that the user-facing unblock entry clears it. No new runnable gate is added here.

## UI Driver
1. `marionette.tap(UiKeys.sidebarContacts)` (`sidebar_contacts_tab`)
2. `marionette.tap({ key: "contact_blocked_users_tab" })` via `UiKeys.contactBlockedUsersTab` (`contact_blocked_users_tab`); wait ~500ms (mobile pushes the route, desktop swaps the pane)
3. `fmt_semantic_snapshot` → record label `S107_blocked_list_seeded`; confirm F's row is present (the `TencentCloudChatContactBlockListItem` carries F's nickname/avatar)
4. Tap F's blocked-list row — there is NO row ValueKey (see Notes); match by F's nickname text / row ref. This `InkWell.onTap` (`tencent_cloud_chat_contact_block_list.dart:139-145`) navigates to `TencentCloudChatUserProfile` for `<toxF>`.
5. Locate the `tL10n.blackUser` operation-bar switch on F's profile (third switch: doNotDisturb / pin / blackUser); it should read ON at `initState` (persistence survived nav, same as S29-A7). Flip it OFF. No confirm dialog.
6. Navigate back to the Blocked-Users tab (mobile: `press_back_button`; desktop: re-tap `contact_blocked_users_tab`); wait ~500ms
7. `fmt_semantic_snapshot` → record label `S107_blocked_list_after_unblock`

## Assertions
- A1: Step-3 Blocked-Users snapshot lists F (row with F's nickname); does NOT show `tL10n.noBlockList` (`tencent_cloud_chat_contact_block_list.dart:74`/`:106`)
- A2: Step-3 `l3_dump_state.blockedUsers[]` contains `<toxF>` (`l3_debug_tools.dart:3598`) — the panel reflects the data layer
- A3: Step-5 `blackUser` switch reads `value: true` at profile `initState` (round-trip: persistence survived the navigation from the blocked-list row — same invariant as S29-A7)
- A4 (primary): after Step 5 unblock, `l3_dump_state.blockedUsers[]` does NOT contain `<toxF>`; `Prefs.black_list_<toxA>` does NOT contain `<toxF>` (`shared_prefs_adapter.dart:40-45`)
- A5: Step-7 Blocked-Users snapshot shows `tL10n.noBlockList`; F's row is absent (the panel re-renders empty after `onBlackListDeleted` updates `_blockList`, gated on `currentUpdatedFields == blockList`, `tencent_cloud_chat_contact.dart:94-96`)
- A6 (S107 vs S29 discriminator): F is STILL in `Prefs.local_friends_<toxA>` / `l3_dump_state.friends[]` after unblock — unblocking does not delete the friendship (mirrors S29-A11)
- A7: `official.get_runtime_errors({})` empty vs Step-0 baseline
- Negative grep: `deleteFromBlackList failed` MUST NOT appear (`tim2tox_sdk_platform.dart` — silent no-op would visually flip-back the switch via `_notifyUserSetFailed`)

## Notes
- L3-pin reason for the unblock leg: the toggle round-trips real `deleteFromBlackList` + `SharedPreferencesAdapter`; the listing itself is hermetic. The data-half is already gated by S29; S107 stays spec-only and does NOT claim a new executable gate.
- Key status verified: `contact_blocked_users_tab` at `tencent_cloud_chat_contact_tab.dart:49` (mobile) / `:113` (desktop). The blocked-list ROW (`TencentCloudChatContactBlockListItem`, `tencent_cloud_chat_contact_block_list.dart:127-153`) has **NO ValueKey** and **no inline unblock button** — it is an `InkWell` that opens the user profile; the actual unblock control is the profile `blackUser` switch (the S29 control). Tap the row by nickname/ref, not by key. If a future patch adds a `contact_block_list_item:<userId>` key + an inline unblock affordance, tighten Step 4 + A1.
- Sibling distinction: S29 is the state-machine test driven from the user-profile switch (asserts Prefs + listener callbacks); S107 is the Blocked-Users TAB rendering + the tab→profile→unblock entry path. The unblock CONTROL is shared (the same `blackUser` switch); the ENTRY and the LISTING are S107-specific.
- Three switches on the profile — disambiguating `blackUser` by exact `tL10n.blackUser` label is locale-fragile (S29 Notes); the proper fix is a `user_profile_block_switch` UiKey (not yet wired).
