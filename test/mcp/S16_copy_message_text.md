# S16 — Copy message text → OS clipboard

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=any(offline OK) friends=1 history=seeded(2)`
**Harness mode**: peerHarness=echo_seeded
**Promotion target**: L3-pinned — ground truth is the OS pasteboard (`pbpaste`), a cross-process read no in-Dart `TestWidgetsFlutterBinding` can observe. L2 could probe `Clipboard.setData` via a channel double, but that proves the call, not that text landed on the system clipboard.
**Status**: covered (received + self variants). Also covered at the widget layer (L1) by WidgetTester real-UI gates that intercept the `SystemChannels.platform` method handler: the real `Copy` menu item handler calls `Clipboard.setData` with the verbatim message text, which is captured and asserted byte-identical to the fixture bubble text.
**Covered-by**: test/ui/chat/message_actions_menu_real_ui_test.dart (desktop), test/ui/chat/message_actions_menu_mobile_real_ui_test.dart (mobile)

## Precondition
- A signed in, plaintext. No `Online` requirement — copy works pre-DHT-bootstrap.
- Seed via `bash tool/mcp_test/restore_echo_peer_seed.sh`: friend F + 2 c2c msgs — `seed_0` (received, `from=<toxF>`, `"heads-up: ci broke"`) and `seed_1` (self, `from=<toxA>`, `"on it"`); both `SEND_SUCC` after history load (`tim2tox_sdk_platform_converters.dart:301-304`).
- Locale pinned `en` (label `Copy`; `tencent_cloud_chat_localizations_en.dart:184`).
- Pasteboard pre-cleared: `pbcopy </dev/null`.
- Copy gated on `defaultMessageMenuConfig.enableMessageCopy` (default true; `home_page_bootstrap.dart:378-383`); menu item id `_uikit_copy_message` (`tencent_cloud_chat_message_item_with_menu_container.dart:339-349`).
- `MCP_BINDING=marionette`.

## Driver
1. Poll snapshot ≤60s for sidebar `<nicknameA>`; baseline `official.get_runtime_errors({})`.
2. `marionette.tap` on `UiKeys.sidebarChats`; `fmt_tap_widget` F's conversation row (label-match `<friendName>`).
3. Snapshot → find target bubble (received: `seed_0`; self: `seed_1`); `marionette.long_press({ref, snapshotId})` (fallback `fmt_long_press`).
4. Snapshot ≤500ms → locate the `Copy` menu item (Flutter `PopupMenuButton` overlay, not OS right-click; PLAYBOOK §7b).
5. `fmt_tap_widget` the `Copy` ref (fallback `marionette.tap({text:"Copy"})`).
6. `pbpaste`; re-clear (`pbcopy </dev/null`) before next variant.

## Assertions
- A1: pre-copy `pbpaste` empty.
- A2 (received): post-tap `pbpaste` == `heads-up: ci broke` exactly (no trailing newline; `Clipboard.setData(ClipboardData(text: selectedText ?? text))` `:346-347` copies `textElem.text` verbatim).
- A3 (self): `pbpaste` == `on it`.
- A4: clipboard byte-identical to rendered bubble text — no `Re:`/quote prefix, no sender-name prepend.
- A5: copy is SILENT — assert via pasteboard only; no `copied` confirmation widget (contrast S31 self-ID copy which shows `idCopiedToClipboard`).
- A6: menu dismisses after tap; post-copy snapshot has no `Copy`/`Reply`/`Forward` labels.
- A7: `official.get_runtime_errors({})` matches Step-1 baseline.
- Negative grep: `A RenderFlex overflowed` must NOT appear when the menu mounts.

## Notes
- No positive log marker on the happy path — the `pbpaste` read IS the assertion.
- Two copy impls: menu item (`:346`) — driven here — and selectable-region copy (`tencent_selectable_region.dart:1103`, `data.plainText`), a separate desktop-selection scenario.
- `Copy` is unconditional for text, unlike Quote/Forward (SEND_SUCC-gated `:350,379`) — works on a SEND_FAIL bubble too (optional negative control).
- Cross-platform pasteboard: Linux `xclip -o -selection clipboard` / `wl-paste`; Windows `Get-Clipboard`.
- Wanted UiKeys (absent in lib/): `message_menu_item_copy`, `message_list_item:<msgID>`; today label-match `Copy` (locale-pinned `en`) is the only handle.
