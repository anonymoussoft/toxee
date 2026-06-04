# S15 — Long-press message → context menu

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online friends=1 history=seeded(2)`
**Harness mode**: peerHarness=none
**Promotion target**: L2 candidate once UIKit-fork per-item `ValueKey('message_menu_item_*')` lands; L3 today because menu lives entirely in UIKit `OverlayEntry` with no toxee builder slot
**Status**: covered (variants 6a/6b/6c)

S15 = menu surface gate only. Tap-item side effects belong to S16/S17/S18.

## Precondition
- Fixture A-friend1-conv-with-history: A signed in, plaintext, friend F in `friends.json`, ≥2 seeded messages: ① `{msgID:"seed_0", fromUserId:<toxF>, text:"heads-up: ci broke", timestamp:<t-3600s>}` ② `{msgID:"seed_1", fromUserId:<toxA>, text:"on it", timestamp:<t-3500s>}` (both SEND_SUCC — converter stamps it on history load)
- Locale pinned to `en` (menu labels: `Copy`, `Reply`, `Forward`, `Delete`, `Multi-Select`, `Recall`)
- Text-translate + sound-to-text plugins initialized (default in toxee HomePage)
- `MCP_BINDING=marionette`

Variants:
- **6a -received** (default): long-press `seed_0` (received text, >120s old)
- **6b -self-old**: long-press `seed_1` (self, >120s old)
- **6c -self-recent**: re-seed `seed_1` with `timestamp: <t-30s>`; long-press it

## Driver
1. Poll snapshot up to 60s for sidebar `<nicknameA>\nOnline`; baseline runtime-errors
2. `marionette.tap` on `UiKeys.sidebarChats` (`sidebar_chats_tab`)
3. `fmt_tap_widget` on F's conversation row (label-match by `<friendName>` until `conv_<toxF>` key lands)
4. Snapshot → find bubble whose label matches target seed text; `marionette.long_press({ref, snapshotId})` (fallback `fmt_long_press`, then `marionette.long_press({key: "message_list_item:seed_0"})` once key lands)
5. Snapshot ≤500ms → enumerate menu items by semantic label
6. Dismiss: `fmt_tap_widget` on a safe ref outside menu Table (chat panel app bar area); shroud `GestureDetector.onTap` fires `_cancelMobileMessageActions`

## Assertions
- A1: snapshot after Step 4 contains the `Copy` label (most stable item — text + non-media + SEND_SUCC)
- A2 (presence): snapshot contains every expected label per variant:
  - **-received**: Copy, Reply, Multi-Select, Forward, Delete, Translate (plugin-gated)
  - **-self-old**: Copy, Reply, Multi-Select, Forward, Delete, Translate
  - **-self-recent**: ALL above + **Recall**
- A3 (absence): snapshot does NOT contain forbidden labels:
  - **-received** / **-self-old**: `Recall`, `Convert to Text`, `Location`
  - **-self-recent**: `Convert to Text`, `Location`
- A4 (-received): `Recall` absent (gating on `_message.isSelf`)
- A5 (-self-old): `Recall` absent (timed-out via `_showRecallButton`'s `timeDiff < recallTimeLimit` branch, `_container.dart:162-184`)
- A6 (-self-recent): `Recall` present (regression-canary that S15 isn't blanket-asserting absence)
- A7: after dismiss, snapshot contains no menu-item labels; bubble Opacity back to 1
- A8: `official.get_runtime_errors({})` matches baseline
- A9: post-dismiss snapshot shows no quoted-message banner, no multi-select toolbar, no forward-picker (S15 leaves zero side effects)
- Negative log grep: `[Tim2ToxSdkPlatform] sendMessage called:`, `[FfiChatService] deleteMessages`, `[FfiChatService] recallMessage`, `A RenderFlex overflowed` must NOT appear

## Notes
- Menu mounted in global `Overlay` `OverlayEntry`, not chat-panel subtree — snapshot includes overlay nodes on observed builds; fall back to `marionette.get_interactive_elements()` if not.
- All visible items are tappable `InkWell`s — no shown-but-disabled state today, so "enabled/disabled" collapses to presence/absence.
- Plugin items (Translate, Convert-to-Text) appear/disappear based on `widget.isTextTranslatePluginEnabled` / `widget.isSoundToTextPluginEnabled`; default fixture has both true. Treat Translate as A2-optional in CI.
- `_uikit_translate` ALSO gates on `!_hasTranslate` (`:532`) — disappears if already translated.
- `fmt_press_key({key:"Escape"})` does NOT dismiss the menu today (no `Shortcuts` wrap).
