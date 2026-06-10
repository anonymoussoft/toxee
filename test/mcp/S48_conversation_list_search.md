# S48 — Conversation list search

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=3+(distinct nicknames) history=≥1 msg/friend`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because exercises pane swap + full-text history scan; needs realistic UIKit conversation tree
**Status**: covered. The interactive global-search FLOW is now covered at the widget layer (L1): `test/ui/search/search_flows_real_ui_test.dart` mounts the REAL `CustomSearch` (global, non-embedded → the production `message_search_field` renders), types a query into the production field, and asserts the REAL `_matchesKeywordCaseInsensitive` filter narrows the rendered contact result rows (`Ali` → Alice only; the shared `neighbour` token → all three), that clearing the field empties the result rows, that re-querying restores the full match set, and that matching is case-insensitive. Only the FFI-backed singleton fetch is replaced (via the new `CustomSearch.rawSearchDataOverride` seam — raw, PRE-FILTER inputs); the filter/render/highlight are production. A new per-contact-row key `UiKeys.searchResultContact(uid)` was added to `custom_search.dart` (the highlighted title is a RichText, so name-based finds are unreliable — this brings contact rows to parity with the already-keyed group/conversation rows). Shell-level pane swap back to the conversation list on clear (A4/A5 conversation-row restore) remains the home surface's territory; this gate owns the result-emptying half. The full-text message-content path is still gated by `custom_search_keys_test.dart` (S93). Shared desktop+mobile (same widget + filter).
**Covered-by**: `test/ui/search/search_flows_real_ui_test.dart`

## Precondition
- One signed-in account A on HomePage.
- ≥3 paired friends with distinct nicknames (e.g. `Alice`, `Bob`, `Charlie`) and one seeded message each in `messages/c2c_<toxX>.json`.
- Distinct-keyword constraint: nickname keyword (`Ali`) appears in no other nickname or message body; message keyword (`pizza`) appears in no nickname or other message body.
- Friends do NOT need to be reachable — search runs entirely against local state.
- `MCP_BINDING=marionette`.

## Driver
1. Wait for `<nicknameA>\nOnline` (60s poll).
2. Confirm on Chats tab (`UiKeys.sidebarChats`; default index 0 on cold start).
3. Locate search `TextField` in conversation header (`TencentCloudChatAppBarSearchItem`, hint `tL10n.search` = `搜索` / `Search` / etc — NOT toxee's `searchHint`).
4. Enter `Ali` into the field (proposed `chat_list_search_field`; today: `fmt_enter_text` on snapshot ref of the only TextField in conversation pane).
5. Right pane swaps to `CustomSearch`; verify filtered result.
6. Clear: tap suffix clear icon (proposed `chat_list_search_clear_button`) OR `fmt_enter_text` empty string (controller-direct fallback works for assertion).
7. Enter `pizza` (message-body keyword) — full-text path via `_searchLocalMessageContent`.

## Assertions
- A1: search `TextField` visible in conversation header with locale-matching hint (`tL10n.search`).
- A2: after `Ali`, snapshot contains `Alice` row only (Bob and Charlie absent); filter via `_matchesKeywordCaseInsensitive` against `friendRemark` / `nickName` / `userID`.
- A3 (screenshot only): result row highlights matched substring via `_buildHighlightedText`.
- A4: widget tree contains `CustomSearch` (not `TencentCloudChatConversationList`) after typing; reverses after clear.
- A5: after clear, all 3 rows restored in original order.
- A6: after `pizza`, `Messages` section shows `Alice` row with subtitle `l10n.messageCount(1)`. **Skipped** if build lacks full-text — verify via `customSearchEmptyState` key.
- A7: exactly ONE `TextField` descendant inside conversation pane (no double field — gates `CustomSearch._isEmbeddedWithParentSearchBar` being true).
- A9: hint text matches one of `搜索` / `搜尋` / `Search` / `検索` / `검색` / `بحث` (UIKit l10n, no ellipsis).
- Negative grep: `[CustomSearch] global history pagination failed`, `[CustomSearch] history pagination failed mid-scan` must not appear.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- The header `TextField` and `CustomSearch` results widget are wired via `_globalSearchWidget` factory; UIKit's desktop-mode passes `keyWord: _searchText` into the factory which trips `_isEmbeddedWithParentSearchBar` (custom_search.dart:201). A7 is the canary for double-field regression.
- `_searchTextListenerHandler` fires `setState` synchronously on each keystroke; `CustomSearch.initState` then calls `_performSearch` without debouncing. Use single-shot `enter_text` (not per-character loop) to avoid swamping rebuilds.
- Full-text `_searchLocalMessageContent` walks every conversation, paginates `getHistoryMessageList` up to `_maxHistoryMessagesPerConversationGlobal = 1000` per conv with `_historySearchPageSize = 200`; early-break once per-conv match found. Wall clock ~500ms on 3-friend fixture.
- If `searchSDK.searchMessages` returns hits directly, local fallback is skipped — same UI shape, different log markers (`[Tim2ToxSdkPlatform] getHistoryMessageList` only on fallback).
- Don't chain S48 after S11/S12 in same session — open-conversation state can change pane mount.
- Phone variant (search bar below AppBar, mobile defaultBuilder) deferred.
- S49 (contact list search) reuses same fixture and `CustomSearch` flow, entered from 联系人 tab.
