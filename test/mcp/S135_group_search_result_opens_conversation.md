# S135 — Group: search result opens the target conversation

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidG] history=seeded(keyword)`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L1/L3 candidate once global/scoped search runners cover group rows; adjacent single-chat sibling is S93
**Status**: covered — **live-validated 2026-06-08** by the `group_search` real-UI gate (`drive_real_ui_pair.dart`, campaign `group-search`, single-instance). A creates a group, opens the REAL global-search overlay via the desktop **Cmd+Ctrl+F** shortcut (the only surface that renders the keyed `message_search_field` — it is NOT on the chats home; that overlay IS flutter_skill-reachable, unlike the group-profile route), types the group name, and taps the KEYED result row — `search_result_group:<gid>` (or the conversation-fallback `search_result_conversation:group_<gid>`), which now carry `UiKeys.searchResultGroup`/`searchResultConversation` added to `custom_search.dart`. Asserts the GROUP chat opens via `_chatSurfaceReadyForAnyGroup(requireGroupId)`. The earlier failures (search field not on chats home; tapping the unkeyed row by name collided with the typed query) are both RESOLVED. **Also covered at the widget layer (L1)** 2026-06-10: `test/ui/search/search_flows_real_ui_test.dart` mounts the REAL `CustomSearch`, types the keyword, asserts the keyed GROUP result row (`UiKeys.searchResultGroup('gidG')`) renders after the real filter, taps it, and asserts the production open-target handler (`_navigateToMessage`) fires exactly once routing `groupID='gidG'` with no userID. A cheap C2C flavor taps the message result row → opens the real `SearchChatHistoryWindow` drill-down → "Open chat" routes `userID` through the same handler. The open-target is observed via the new `CustomSearch.onOpenConversation` seam (replaces only the singleton/facade navigation; the row render + onTap wiring are production). Shared desktop+mobile.
**Covered-by**: `test/ui/search/search_flows_real_ui_test.dart`

## Precondition
- Group `<gidG>` contains a unique seeded keyword in its history.
- The global search UI is reachable from the running shell.

## UI Driver
1. Open search and enter the seeded keyword.
2. Wait for the result row keyed as `UiKeys.searchResultMessage("group_<gidG>")`.
3. Tap the result row.

## Assertions
- The tapped result opens the target group conversation.
- The opened conversation highlights or reveals the matching history context.
- No runtime errors appear vs baseline.

## Notes
- This is the group analog of the search-open leg from S93.
- The key shape already accepts `group_<gid>` conversation IDs.
