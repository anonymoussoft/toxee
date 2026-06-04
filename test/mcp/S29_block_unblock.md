# S29 — Block + unblock a user

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1 (blocklist starts empty for F)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — exercises the state machine across UIKit operation-bar switch + Tim2Tox `add/deleteFromBlackList` + `SharedPreferencesAdapter` round-trip. Sibling of S28 (same profile-page entry, different control).
**Status**: covered (state-machine assertions only — see A13 caveat)

## Precondition
- Account A logged in, plaintext, sidebar Online (poll 60s)
- `Prefs.local_friends:<toxA>` contains `<toxF>`; `Prefs.friend_nickname:<toxF>` set
- **`Prefs.black_list_<toxA>` MUST be absent or empty** — pre-flight `defaults delete com.toxee.app 'flutter.black_list_<toxA>'` so toggle-ON is the actual ON-toggle (not the no-op of an already-on state)
- F does NOT need to be online — blocklist is pure prefs + listener notify

## Driver
1. `marionette.tap({ key: "sidebar_contacts_tab" })`; tap F's row to push `TencentCloudChatUserProfile`
2. Locate the `tL10n.blackUser` operation-bar row (third of three switches: doNotDisturb / pin / blackUser). Tap to flip ON. No confirm dialog.
3. Navigate to the Contacts-tab `blocked_users` page (`tL10n.blockList`, `Icons.block_outlined`). Mobile: `Navigator.push`; desktop: right-pane swap.
4. Tap F's row in the blocked-users list → re-opens the same `TencentCloudChatUserProfile` (switch should now read ON at `initState`)
5. Flip the `blackUser` switch OFF
6. Navigate back to blocked-users page; verify empty

## Assertions
- A1-ON: `blackUser` switch `value: true` after step 2
- A1-OFF: `blackUser` switch `value: false` after step 5
- A2-ON: blocked-users page lists F; does NOT show `tL10n.noBlockList`
- A2-OFF: blocked-users page shows `tL10n.noBlockList`; F absent
- A3: post-ON, `Prefs.black_list_<toxA>` (legacy full-toxId key, NOT prefix) contains `<toxF>`
- A4: post-OFF, `Prefs.black_list_<toxA>` does NOT contain `<toxF>`
- A5: log emits `onBlackListAdd` with userID=<toxF> after step 2
- A6: log emits `onBlackListDeleted` with userID=<toxF> after step 5
- A7 (round-trip): step 4's profile remount shows switch ON at `initState` (proves persistence survived the navigation)
- A11 (S29 vs S28 discriminator): F is STILL in `Prefs.local_friends:<toxA>` after both toggles — friendship intact
- A12: `c2c_<toxF>` row still present in Chats tab between step 2 and step 3 (block does not remove the conversation)
- A13 (negative — documented gap, NOT a bug to fix in this test): a peer message from F IS still delivered to A's history while blocked. The blocklist is a local UI hide-only filter per the comment at `tim2tox_sdk_platform.dart:7773-7782`; nothing on the receive path consults it (grep for `getBlackList`/`isBlocked` returns only writer callsites). If a future patch adds the receive-side filter, flip A13's sign.
- Negative grep: `addToBlackList failed: no preferences service available`, `addToBlackList failed: user not logged in`, `deleteFromBlackList failed` MUST NOT appear (these mean the platform silently no-op'd and UIKit will visually flip-back the switch via `_notifyUserSetFailed`)

## Notes
- Three switches on the page — disambiguating `blackUser` by exact `tL10n.blackUser` label match is locale-fragile. The `user_profile_block_switch` UiKey (UIKit fork) is the proper fix.
- Pref key uses LEGACY full-toxId scheme `black_list_<toxA>` (NOT the 16-char-prefix scheme of newer per-account keys); see `lib/adapters/shared_prefs_adapter.dart:40-45`
- `TencentCloudChatContactBlockListState` only re-renders when `currentUpdatedFields == blockList`; verify A6's listener fired or the page goes stale
- Settings page has NO "Blocked users" entry — entry is the Contacts-tab `blocked_users` tab item (`tencent_cloud_chat_contact.dart:302-312`)
- The "messages dropped while blocked" playbook prose is a known divergence; closing it requires a behavior change in `FakeMessageManager.start` to consult `Prefs.getBlackList` — track separately, NOT a test bug
