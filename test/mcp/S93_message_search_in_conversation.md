# S93 — Message search within a conversation (full-text + highlight)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1(F) history=seeded(≥3 msgs, one carrying a distinct keyword)`
**Harness mode**: peerHarness=none (search runs entirely against local persisted history — no live peer needed once seeded)
**Promotion target**: L3-pinned because it exercises the UIKit/CustomSearch surface (search field → result list → drill-down with keyword highlight) which needs a realistic mounted conversation tree; the data path itself is local.
**Status**: L3-MANUAL (no executable gate yet). Covers the MESSAGE-SEARCH half of feature **L3** (自定义搜索 消息/联系人/群组 + 高亮, `lib/ui/search/custom_search.dart`). Siblings: S48 covers conversation-list search, S49 covers contact search (and HAS an executable gate `run_fixture_c_contact_search.sh`). S93 covers in-conversation / message-content search + the per-message highlight drill-down (`SearchChatHistoryWindow`). The core search field + result-row anchors now exist (`message_search_field`, `search_result_message_<convId>`, `search_history_message_<msgId>`); remaining work is wiring a stable invoke-search seam from the live conversation surface into a runner.

## Precondition
- Account A signed in, plaintext profile, `autoLogin=true`.
- Friend F with seeded `chat_history` for the C2C conversation: ≥3 messages, exactly one containing a distinct keyword (e.g. `pizza`) that appears in no other message body and in no nickname — so the match set is unambiguous (same distinct-keyword discipline as S48 `S48_conversation_list_search.md:11`).
- The conversation has enough history that in-memory + paginated fallback both have something to scan (the scoped path paginates `getHistoryMessageList` up to `_maxHistoryMessagesPerConversation = 2000`, `custom_search.dart:81`, `:312`).
- `MCP_BINDING=marionette`.

## Driver
Two driveable seams; both reach the message-content search:
1. Wait for sidebar `<nicknameA>\nOnline`; baseline `official.get_runtime_errors({})`.
2. **Scoped (in-conversation) path** — open F's conversation, invoke the in-chat search. `CustomSearch` is constructed with `userID: <toxF>` (non-global), so `_isGlobalSearch` is false (`custom_search.dart:198`) and it routes to the scoped branch: `searchSDK.searchMessages(keyword, conversationID: 'c2c_<toxF>')` with an in-memory + persisted-history fallback (`custom_search.dart:288-350`).
3. Enter `pizza` into `UiKeys.messageSearchField` (`message_search_field`); 300ms debounce fires `_performSearch` (`custom_search.dart:508-509`).
4. Tap `UiKeys.searchResultMessage("c2c_<toxF>")` → `SearchChatHistoryWindow` opens with the matched message list and per-message highlight. In the drill-down, assert rows by `UiKeys.searchHistoryMessage("<msgId>")`.
5. (Alternative GLOBAL seam) Cmd/Ctrl+F mounts `CustomSearch` in global mode (`home_page.dart:1180-1226`); typing `pizza` falls through `searchSDK.searchMessages` → `_searchLocalMessageContent` (`custom_search.dart:264-265`) which walks every conversation and surfaces F under the `Messages` section. This is the S48 global path, reached here as a fallback to assert message-content matching when the scoped overlay can't be mounted.

## Assertions
- A1: the in-conversation search `TextField` is visible at `UiKeys.messageSearchField` with locale hint `l10n.searchHint` (`custom_search.dart:475`, en = `Search...`).
- A2 (match, headline): after `pizza`, the result surfaces exactly the F conversation at `UiKeys.searchResultMessage("c2c_<toxF>")`; subtitle is `l10n.messageCount(<n>)` where `<n>` ≥ 1.
- A3 (highlight, screenshot-only): the matched substring `pizza` is rendered highlighted — `_buildHighlightedText` in the result row (`custom_search.dart:636`) and `_buildHighlightedSummary` in the drill-down (`search_chat_history_window.dart:530`). No ValueKey on the highlight span → screenshot assertion only.
- A4 (no-match): a keyword present in NO message body yields the empty state `l10n.noResultsFound` (`custom_search.dart:559`, en = `No results found`).
- A5 (drill-down): tapping the result opens `SearchChatHistoryWindow`, and at least one `UiKeys.searchHistoryMessage("<msgId>")` row is present with the keyword pre-filled (`search_chat_history_window.dart:52-53`).
- Negative grep: no `[CustomSearch] history pagination failed mid-scan` (`custom_search.dart:326`); `official.get_runtime_errors({})` baseline-clean.

## Notes
- Why L3-manual not gated: the per-result anchors now exist, but the live “invoke scoped in-conversation search overlay from a mounted chat header” seam is still not runner-stable; the current global Cmd/Ctrl+F flow belongs to S48. There is still no `run_fixture_c_*` for this scoped surface.
- Promotion state: `message_search_field`, `search_result_message_<convId>`, and `search_history_message_<msgId>` are now shipped. The remaining gate work is a stable scoped-search entry trigger plus an executable fixture around it.
- The scoped vs global split matters: scoped (`userID` set) hits `searchMessages(conversationID:)` then the per-conversation fallback (`custom_search.dart:294-350`); global (Cmd/F) hits `_searchLocalMessageContent` across ALL conversations (`custom_search.dart:88-154`). S93 asserts the SCOPED path primarily; the global path is S48's territory, reused only as a fallback seam.
- Data-layer alternative (out of this spec's scope but the cheap honest gate): the message-content match logic could be unit-tested directly against `MessageHistoryPersistence` / `getHistoryMessageList` without the overlay — that would be an L2 test, not an L3 MCP gate, and would not cover the highlight render.
- 300ms `_performSearch` debounce on every keystroke (`custom_search.dart:509`) — single-shot `enter_text`, not per-character, and budget the debounce before snapshotting (same discipline as S48/S49).
