# S57 — Theme switch with chat open (in-flight rebuild robustness)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online history=≥3-msgs theme=light`
**Harness mode**: peerHarness=none
**Promotion target**: L2 candidate — hermetic test with pumped `MaterialApp` and stub chat panel can cover A1/A2/A3/A11; L3-pinned today because pixel-sample assertions (A4/A5/A6) require a real render and DHT-online sidebar.
**Status**: covered.

## Precondition
- Account A signed in, online, plaintext profile.
- At least one conversation with ≥3 prior text messages on disk (`account_data/<toxA>/history/`), ideally including one emoji message (`🦊`) and one custom-face sticker (`[gcs00]`).
- `Prefs.themeMode == "light"` before launch.
- `MCP_BINDING=marionette`.

## Driver
1. Wait for sidebar `<nicknameA>\nOnline`; capture `s57_step1_light_home.png`.
2. Tap a conversation row → message panel mounts (header + ≥3 bubbles + input field). Save `s57_step2_light_chat.png`.
3. Focus the message input and type `"in-flight typing — theme switch test 🎨"` via `fmt_enter_text` (or `marionette.enter_text` once `message_input_field` key lands). Save `s57_step3_light_chat_with_text.png`.
4. `marionette.tap({ key: "sidebar_settings_tab" })` — IndexedStack preserves chat State.
5. Re-snapshot, find the "Dark" / "深色" segment in the `SegmentedButton<ThemeMode>` at `global_settings_section.dart:210-228`, tap via `fmt_tap_widget`. Wait 600 ms (covers 400 ms `themeAnimationDuration`). Save `s57_step5_dark_settings.png`.
6. `marionette.tap({ key: "sidebar_chats_tab" })` → chat panel returns in dark mode. Save `s57_step6_dark_chat.png`.
7. Back to Settings → tap "Light" / "浅色" segment → wait 600 ms → return to Chats. Save `s57_step8_light_chat_again.png`.

## Assertions
- A1/A2: input field value equals `"in-flight typing — theme switch test 🎨"` in both `s57_step3` and `s57_step6` snapshots — `TextEditingController` survived the rebuild.
- A3: input still focused after Step 6, or tap restores focus at end of buffer.
- A4: chat-header background mean-luminance drops ≥40% between Step 3 and Step 6 (pixel-sample inside header bounds).
- A5: self-bubble color flips from `#DBEAFE` → `#1E3A8A` range; others bubble from white → `#1E293B` range.
- A6: sticker glyph crop is byte-equal between Step 3 and Step 6 (raster asset, theme-independent).
- A7: Step 8 chat panel matches Step 3 within pixel-hash tolerance.
- A8: log between Step 5 and Step 6 contains no `A RenderFlex overflowed`.
- A9: `get_runtime_errors({})` no new entries beyond Step 1 baseline.
- A10: `defaults read com.toxee.app 'flutter.themeMode'` → `"dark"` after Step 5, `"light"` after Step 7.
- A11: `TencentCloudChatTheme().brightness` matches `AppTheme.mode` post-switch (the `_syncUIKitThemeBrightness` listener at `main.dart:234-239` is the line under test).
- Full-run negative grep: no `TextEditingController used after being disposed`.

## Notes
- 400 ms `themeAnimationDuration` (`main.dart:287`) — wait ≥600 ms before pixel sampling to avoid mid-transition frames.
- IndexedStack at `home_page.dart:1343-1348` keeps all four tab subtrees alive across tab switches; this is what preserves the message input controller.
- Set window width <900px before run (single-pane mode) so snapshot shape is predictable; master-detail layout has different node hierarchy.
- `Prefs.themeMode` write and UIKit `init(brightness:)` are both silent today — A10/A11 must be verified via prefs/live-Dart, not log grep.
- Locale fallback: assert on English segment labels in CI default; S38 locale rotation requires keyed segments.
