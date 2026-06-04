# S31 — Self Tox ID display + copy

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK)`
**Harness mode**: peerHarness=none
**Promotion target**: Could be L2 if a `Clipboard` test-double + a SnackBar widget probe were wired; today L3 because the host pasteboard (`pbpaste`) is the ground truth for the clipboard assertion. Runs both ProfilePage (V1) and Settings (V2) entry points in one session for cross-check.
**Runner gate**: `tool/mcp_test/scenarios/l3_self_id.json`
**Status**: covered — the DATA half is now an executable hermetic gate (asserts `l3_dump_state.currentAccountToxId` exposes the seeded self id), while the OS-clipboard copy itself stays verified out-of-band via `pbpaste` (like S16). The gate asserts the id value is exposed, not the clipboard write.

## Precondition
- Account A signed in (plaintext profile)
- `Prefs.getCurrentAccountToxId()` returns the real 76-hex toxId (so `showSelfProfile`'s `storedToxId != null && isNotEmpty` branch wins — see `sidebar.dart:55-59`)
- macOS pasteboard pre-cleared (`pbcopy </dev/null`)
- No `Online` requirement — copy must work pre-DHT-bootstrap (the common real-world moment users want to share their ID)
- `EXPECTED_TOXID` captured from `defaults read com.toxee.app 'flutter.current_account_tox_id'` — must be 76 hex chars (wire key `flutter.current_account_tox_id` per `lib/util/prefs.dart:62`)

## Driver — V1 (Profile)
1. Tap sidebar `_UserAvatar` via `marionette.tap({ key: "sidebar_user_avatar" })` (`UiKeys.sidebarUserAvatar`) → opens `ProfilePage` in Dialog (desktop) or MaterialPageRoute (mobile)
2. Verify `ProfileToxIdSection` renders the full 76-hex string in the keyed `SelectableText` `profile_tox_id_selectable_text`
3. Tap the keyed Tox ID copy control `marionette.tap({ key: "profile_tox_id_copy_button" })` (`UiKeys.profileToxIdCopyButton`). The QR copy button is separately anchored as `profile_qr_copy_button`, so the two `Copy` actions are no longer label-disambiguated in ProfilePage.
4. Capture SnackBar within ~1s (auto-dismisses ~4s); shell `pbpaste` to compare
5. Close ProfilePage (`marionette.press_back_button` works on both Dialog and route)

## Driver — V2 (Settings)
6. Shell: `pbcopy </dev/null` to clear between variants
7. `marionette.tap({ key: "sidebar_settings_tab" })`
8. Tap the keyed Settings-page copy control `marionette.tap({ key: "settings_copy_tox_id_button" })` (`UiKeys.settingsCopyToxIdButton`) in the Tox ID row of the Account card.
9. Shell `pbpaste` and compare
10. Optional Step 9 cross-check: `fmt_evaluate_dart_expression({ expression: "FakeUIKit.instance.ffiService.accountKey" })` should return `EXPECTED_TOXID`

## Assertions
- A1: pre-V1 clipboard empty
- A2 (primary): V1 clipboard == `EXPECTED_TOXID`, 76 hex chars matching `^[0-9a-fA-F]{76}$`
- A4: V1 SnackBar with localized `idCopiedToClipboard` text appeared
- A5: clipboard cleared between V1 and V2
- A6 (primary): V2 clipboard == `EXPECTED_TOXID`
- A8: V2 SnackBar `idCopiedToClipboard` appeared
- A9 (cross-check): V1 clipboard == V2 clipboard (both entry points agree)
- A10: clipboard == `FfiChatService.accountKey` (in-process eval) or last 76-hex match in log
- A11 (truncation guard): displayed `SelectableText` in ProfileToxIdSection is the full 76 chars, NOT ellipsised
- A12: `[ProfilePage] Failed to copy Tox ID` MUST NOT appear in log
- A14 (placeholder leak guard, primary): clipboard NEVER equals `FlutterUIKitClient` (the V2TIM login placeholder); regression here would mean the copy handler regressed to `service.selfId` instead of `service.accountKey` / `Prefs.getCurrentAccountToxId`
- A13: `official.get_runtime_errors({})` empty vs Step 1 baseline

## Notes
- **Runner gate (data half)**: `tool/mcp_test/scenarios/l3_self_id.json` (run via `dart run tool/mcp_test/run_l3_scenarios.dart`) is read-only — no steps, no mutation, no peer. It asserts `l3_dump_state.currentAccountToxId` (sourced from `Prefs.getCurrentAccountToxId()`, the same persisted self identity the copy UI reads) contains the seeded account prefix `8895A8D6`. This proves the id value is *exposed* to the copy path; the actual `Clipboard.setData` write is NOT covered by the gate and stays verified out-of-band via `pbpaste` (the A2/A6 assertions above), exactly like S16.
- The copy path is SILENT on the happy path — no positive log markers; assertions are clipboard contents + SnackBar visibility + negative log markers
- Profile-side anchors are shipped: `sidebar_user_avatar`, `profile_tox_id_copy_button`, `profile_tox_id_selectable_text`, and `profile_qr_copy_button`. The Settings-page copy button is also now keyed as `settings_copy_tox_id_button`, so V2 no longer depends on tooltip text.
- Settings copy currently uses raw `ScaffoldMessenger.showSnackBar` (default Material style) while ProfilePage uses `AppSnackBar.showSuccess` (green tint) — assert via text content not visual style. Consolidating is tracked separately.
- Both display sites wrap the hex in `Directionality(LTR)`; clipboard contents must always be LTR — `Clipboard.setData(text: widget.userId)` short-circuits the bidi reorder concern
- One of the cheapest scenarios in the suite (20–40s warm) — good smoke-tier candidate
- On Linux: `xclip -o -selection clipboard` (X11) or `wl-paste` (Wayland). On Windows: `powershell -Command Get-Clipboard`.
