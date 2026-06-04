# S49 — Contact list search (tap, filter, clear, empty state)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online friends=3 history=clean`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because needs live DHT bootstrap to reach Online and exercise `CustomSearch` overlay through Cmd/Ctrl+F shortcut.
**Status**: covered — A-block via the Cmd/F overlay; B-block now FIXED in the UIKit fork (the contact AppBar search builder rendered a real TextField with key `contact_search_field` + a query→AZ-list filter) and gated by `tool/mcp_test/run_fixture_c_contact_search.sh` (`l3_contact_search` runs the same case-insensitive remark/nick/userID filter: full→1, matching prefix→1, non-match→0). Validated live 2026-06-01.

## Precondition
- Account A signed in, plaintext profile, `autoLogin=true`.
- Exactly three friends with disjoint-prefix nicknames `Alice`, `Bob`, `Carol` (via `friend_nickname_<F>_<prefA16>` scoped prefs).
- No `friend_remark_<F>_<prefA16>` keys present (remarks would shadow nicknames in `_getShowName`).
- No groups, no message history for the three friends (clean `CustomSearch` global search).
- `MCP_BINDING=marionette`.

## Driver
1. Wait for sidebar `_UserAvatar` label to match `^<nicknameA>\nOnline$` (≤60s for DHT).
2. `marionette.tap({ key: "sidebar_contacts_tab" })` → verify rows `Alice`, `Bob`, `Carol` render. Prefer `UiKeys.contactListTile("<toxId>")` (`contact_list_item:<toxId>`) whenever the fixture knows the exact friend IDs; label-match remains the fallback.
3. Snapshot contact tab AppBar; record absence of `TextField` (B-block negative anchor — known gap).
4. `marionette.press_key({ key: "f", modifiers: ["meta"] })` to fire `_OpenSearchIntent` (`home_page.dart:1164-1181`) and mount `CustomSearch` overlay.
5. `fmt_enter_text` (autofocused field) → `"Al"`; wait 300 ms debounce.
6. Snapshot overlay results — verify exactly one `Alice` row, no `Bob`/`Carol`.
7. `marionette.enter_text({ text: "" })` to clear → empty body.
8. Enter `"zzz_no_such_friend"` → empty-state placeholder (`l10n.searchNoResults`).
9. Tap close `IconButton(Icons.close)` (`custom_search.dart:454-458`) → return to Contacts tab.

## Assertions
- After Step 2: contact AZ-list contains exactly the three labeled rows.
- After Step 5: overlay body has section header `l10n.contacts` and a single result row labeled `Alice`; no `Bob`/`Carol` nodes.
- After Step 8: empty-state placeholder rendered; no Contacts/Groups/Messages headers.
- After Step 9: original three rows still in same order — filter never mutated source list.
- Prefs invariant: `friend_nickname_<F>_<prefA16>` and `local_friends:<prefA16>` unchanged from pre-flight (`diff` against snapshot).
- Negative log grep on filter window: no `tox_friend_send`, `setFriendInfo`, `setFriendRemark` — filter is pure local Dart.
- `get_runtime_errors({})` baseline-clean across the overlay mount/unmount.

## Notes
- B-block (in-page contact AppBar search) is XFAIL until upstream `TencentCloudChatAppBarSearchItem` is patched or toxee adds a `ContactAppBarSearchOverride`. Do not fail the run on B.
- Cmd/F path requires `marionette.press_key` keyboard injection — not all debug profiles allow it.
- 300 ms `_performSearch` debounce on every keyword change; budget for it before snapshotting.
- `_emitContacts` 5s steady-state poll can interleave with the overlay's `_contactsList` snapshot; benign because overlay holds its own copy.
