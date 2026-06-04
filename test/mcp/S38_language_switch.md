# S38 — Language switch (i18n delegate chain end-to-end)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online sessionPwd=any locale=fresh`
**Harness mode**: peerHarness=none
**Promotion target**: L2 candidate for non-RTL flips (zh↔en); L3-pinned for Arabic RTL because Directionality propagation through `MaterialApp.locale` needs full widget tree
**Status**: covered

## Precondition
- One signed-in account A on HomePage.
- `defaults delete com.toxee.app 'flutter.language_code'` pre-test so picker starts from system-resolved locale.
- `MCP_BINDING=marionette`.

## Driver
1. Baseline snapshot: record sidebar labels (`Chats / Contacts / Settings` en; `聊天 / 联系人 / 设置` zh).
2. `marionette.tap({key: "sidebar_settings_tab"})`.
3. Tap collapsed language row (proposed `settings_language_row`; today: match the node whose label equals current display value e.g. `English` / `简体中文`).
4. List expands with **6** options in order: `English`, `简体中文`, `繁體中文`, `日本語`, `한국어`, `العربية`. No "Follow system" row.
5. Tap target locale (proposed per-locale keys `settings_language_option_en` / `_zh_hans` / `_zh_hant` / `_ja` / `_ko` / `_ar`).
6. Run three flips: en → zh_Hans, zh_Hans → en, zh_Hans → ar (Arabic — the RTL load-bearing case).
7. Wait ≤500ms for `MaterialApp` rebuild before snapshotting.

## Assertions
- **Sidebar both delegate chains**: `Chats` / `Contacts` / `Settings` (UIKit delegate via `tL10n`) AND `Applications` (toxee `AppLocalizations` delegate, `sidebar.dart:236`) all flip in one tick.
- **Settings titles**: `Appearance` / `Language` / `Downloads Directory` / `Auto Download Size Limit` flip via `AppLocalizations`.
- Selected language row gets `radio_button_checked` icon.
- **Arabic RTL**: nearest `Directionality` ancestor of sidebar reports `textDirection == rtl`; sidebar avatar hit-tests on right edge instead of left; chevron position mirrors.
- **Persistence**: `defaults read com.toxee.app 'flutter.language_code'` returns `en` / `zh_Hans` / `ar` matching the picker selection (concat `lang_Script` per `prefs.dart:523`). The wire key is `language_code`, see `lib/util/prefs.dart:42`.
- After Arabic flip, no LTR survivors in sidebar/settings region except brand strings (`toxee`), Tox ID hex, monospace paths.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- 7 `supportedLocales` (`ar / en / ja / ko / zh / zh_Hans / zh_Hant`) but picker shows 6 (no bare `zh`; bare entry exists for system-locale fallback resolution).
- Two `setLocale` paths sync UIKit: `main.dart:273` root rebuild + `settings_page.dart:927` post-frame callback. UIKit labels can lag toxee labels by one frame — re-snapshot if mixed-locale state.
- `_resolveSystemLocale` only runs at first launch with empty Prefs; picker tests the explicit-set path.
- `cfprefsd` cache: `killall cfprefsd` before `defaults read` if value not flushed.
- The `Applications` sidebar label is the canary that proves `AppLocalizations` delegate re-resolved (vs UIKit-only).
