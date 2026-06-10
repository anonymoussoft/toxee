# S20 — Delete entire conversation (friendship preserved)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any friends=1 history=present(c2c with F)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned because the flow exercises toxee's overridden conversation context menu (`home_page.dart:1442-1577`) plus a confirmation dialog plus the FfiChatService disk-cleanup chain — needs the real binary's post-frame handler registration. Sibling of S28 (which deletes the friend itself); the discriminator is friendship intact vs not.
**Status**: covered at the widget layer (L1) — friendship-preservation surface (delete-conversation dialog title is deleteConversationTitle, distinct from any friend-removal dialog; confirm button is the conversation-delete key) is gated by `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart` (test "S20 C2C delete dialog labels the action as delete-conversation (not delete-friend)"). Full data-layer gates (A3+A4+A7+A9) require the live L3 path.
**Covered-by**: `test/ui/conversation/conversation_row_menu_c2c_real_ui_test.dart`

## Precondition
- **Seeded fixture**: `bash tool/mcp_test/restore_echo_peer_seed.sh` — restores `~/Library/Containers/com.toxee.app/Data/...` (profiles + account_data) + Prefs (`flutter.account_list`, `flutter.current_account_tox_id`, `flutter.local_friends_<prefix>`, scoped per-account keys) from cached tarball at `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst`. The restore wipes existing toxee state.
- **Seeded state**: after restore, the active account is `echo_seeded_test` (auto-login enabled); 1 friend (the echo peer) is in the contact list with status "Offline" (since the bot isn't running for seeded scenarios); chat history contains 3 ping/pong message pairs.
- **Cache miss**: if `tool/mcp_test/fixtures/.cache/echo_peer_seeded_<machine_id>.tar.zst` doesn't exist on this machine, restore auto-calls `regen_echo_peer_seed.sh` to populate. Generation takes a few minutes (launches Toxee, drives via marionette, snapshots). Subsequent restores are fast.
- **Echo peer NOT running**: the bot is intentionally offline during this scenario — the friend appears Offline. Tests that depend on peer being Online belong in `peerHarness=echo_live` scenarios.
- Account A logged in, plaintext profile
- `local_friends:<toxA>` contains `<toxF>`; `friend_nickname:<toxF>` set to a unique label
- `<accountDataRoot>/chat_history/<toxF_normalized64>.json` exists with at least one text message in each direction
- Sidebar/post-frame handler registration has fired (wait for sidebar `<nicknameA>\nOnline`/`Connecting`)
- F's conversation row appears in the Chats tab semantic tree

## Driver
1. `marionette.tap({ key: "sidebar_chats_tab" })` (`UiKeys.sidebarChats`)
2. Semantic snapshot, locate row for F by nickname; long-press via `fmt_long_press({ ref, durationMs: 600 })` (or `marionette.long_press({ text: "<nicknameF>" })`)
3. In the popup, prefer `marionette.tap({ key: "conversation_context_menu_delete_item" })` (`UiKeys.conversationContextMenuDeleteItem`). Label-match on `l10n.delete` ("Delete" / "删除") remains the fallback if the key lookup regresses.
4. In the `AlertDialog` (title `l10n.deleteConversationTitle`), prefer `marionette.tap({ key: "delete_conversation_confirm_button" })` (`UiKeys.deleteConversationConfirmButton`). Label-match on the red `l10n.delete` action remains the fallback.
5. Re-snapshot; switch to Contacts tab and re-snapshot

## Assertions
- A3: F's conversation row absent from Chats semantic tree
- A4: `<accountDataRoot>/chat_history/<toxF_normalized64>.json` removed (note: filename is normalized 64-hex, no `c2c_` prefix)
- A5: `<toxF_normalized64>.json.bak` removed if it existed
- A6: `Prefs.pinned_conversations` no longer contains `<toxF>`
- A7 (primary discriminator vs S28): `Prefs.local_friends:<toxA>` still contains `<toxF>`
- A8: `Prefs.friend_nickname:<toxF>` still present
- A9: F still appears in Contacts tab
- Log markers in order: `[FakeConversationManager] deleteConversation: START - conversationID=c2c_<toxF>` → `[FfiChatService] clearC2CHistory:` → `[FakeConversationManager] deleteConversation: DONE` → `[FakeChatDataProvider] Removed conversation c2c_<toxF> from _convMap via onConversationDeleted`
- Negative grep: `[FfiChatService] deleteFriend` MUST NOT appear (would indicate S28-style removal)
- `official.get_runtime_errors({})` empty vs Step 0 baseline

## Notes
- The seeded friend (echo peer) itself stays in the contact list after the conversation delete; only the conversation gets deleted. This is the primary discriminator from S28 (which removes the friend itself). A7+A9 are the gates.
- Cleanup is synchronous — `FakeUIKit.refreshConversations()` kicks immediately (no 5s poll wait, unlike S28)
- `deleteConversationBody` copy currently lies ("Message history stays on disk") while implementation deletes it — track separately; do not assert on the body text
- If the upstream menu (Hide/Pin/Delete labels) opens instead of toxee's (Pin/Mark as read/Delete), the post-frame handler registration regressed — grep log for `Failed to register conversation context-menu handlers`
- Real UiKeys now shipped for this flow: `conversation_context_menu_delete_item`, `delete_conversation_confirm_button`, and the existing conversation row key `conversation_list_item:<convId>`
