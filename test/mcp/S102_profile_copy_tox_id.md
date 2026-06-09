# S102 — Self-profile: Copy Tox ID button → OS clipboard

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the assertion is the host pasteboard (`pbpaste`) cross-process — `Clipboard.setData` writes to the OS pasteboard, and in-process `Clipboard.getData` is not a faithful cross-process check (see §3 UI_TEST_LAYERING "OS clipboard cross-process verification → L3 only"). The button-fires-`_copyToxId` wiring could be L1 (pump `ProfileToxIdSection`, fire `onCopy`, assert the callback), but the actual clipboard write stays L3.
**Status**: covered (L1 WidgetTester real-UI gate — test/ui/profile_copy_tox_id_real_ui_test.dart). The L1 gate proves the REAL `_copyToxId` handler writes the correct 76-hex toxId to the `flutter/platform` clipboard channel (`Clipboard.setData`), verifies the `SelectableText` renders the full 76-char id, asserts the snackbar appears, and guards against the `FlutterUIKitClient` placeholder-leak regression. Cross-process ground truth (`pbpaste` on the OS pasteboard) stays L3 — that is a host-process concern outside the widget-test sandbox.
**Covered-by**: test/ui/profile_copy_tox_id_real_ui_test.dart
**Mobile-parity**: `_copyToxId` and `ProfileToxIdSection` are shared Dart (`lib/ui/profile/profile_edit_fields.dart`, `lib/ui/profile_page.dart`) — identical on iOS/Android; only the host-side pasteboard-read command differs per platform (`pbpaste` on macOS, `xclip`/`wl-paste` on Linux, `Get-Clipboard` on Windows). This L1 gate covers all targets.

## Precondition
- Account A signed in, plaintext profile; self-profile reachable via `sidebarUserAvatar`.
- `Prefs.getCurrentAccountToxId()` returns the real 76-hex toxId, so `showSelfProfile` takes the `storedToxId != null && isNotEmpty` branch (`sidebar.dart:55-59`) and `ProfilePage.userId` is the real id. `ProfileToxIdSection` receives `userId: widget.userId` and copies exactly that (`_copyToxId` → `Clipboard.setData(text: widget.userId)`, `profile_page.dart:303`).
- macOS pasteboard pre-cleared (`pbcopy </dev/null`).
- No `Online` requirement — copy must work pre-DHT-bootstrap (the common real-world share-my-id moment).
- `EXPECTED_TOXID` captured from `defaults read com.toxee.app 'flutter.current_account_tox_id'` (wire key `flutter.current_account_tox_id`, `lib/util/prefs.dart:62`) — 76 hex chars.

## Executable Driver

```bash
dart run tool/mcp_test/run_l3_scenarios.dart tool/mcp_test/scenarios/l3_self_id.json
```

DATA half only: read-only, asserts `l3_dump_state.currentAccountToxId` exposes the seeded self id (`contains B4C5B0957C662A83`, the echo fixture account prefix) — the same persisted identity the copy UI reads via `Prefs.getCurrentAccountToxId()`. It proves the value is exposed to the copy path; the `Clipboard.setData` write is NOT covered and stays verified out-of-band via `pbpaste` (A2 below).

## UI Driver
1. Shell: `pbcopy </dev/null` to clear the pasteboard.
2. `marionette.tap` `UiKeys.sidebarUserAvatar` (`sidebar_user_avatar`, `sidebar.dart:400`) → `ProfilePage` mounts.
3. Verify `UiKeys.profileToxIdSelectableText` (`profile_tox_id_selectable_text`, `profile_edit_fields.dart:340`) renders the full 76-hex string in the snapshot (the read-only Tox-ID panel; no edit-mode toggle needed — `ProfileToxIdSection` is always present in `_buildContent`).
4. `marionette.tap` `UiKeys.profileToxIdCopyButton` (`profile_tox_id_copy_button`, `profile_edit_fields.dart:304`) — the `TextButton.icon` whose `onPressed: onCopy` is `_copyToxId`. The QR copy is a SEPARATE button (`profile_qr_copy_button`, S103), so the two `Copy` actions are key-disambiguated.
5. Capture the SnackBar within ~1s (auto-dismisses ~4s). Shell `pbpaste`.

## Assertions
- A1: pre-tap clipboard empty (Step 1 cleared it).
- A2 (primary): `pbpaste` == `EXPECTED_TOXID`, matching `^[0-9a-fA-F]{76}$`. This is the cross-process clipboard ground truth.
- A3: the displayed `SelectableText` (`profile_tox_id_selectable_text`) is the full 76 chars, NOT ellipsised (truncation guard — it's wrapped in `Directionality(LTR)`, `profile_edit_fields.dart:337-348`).
- A4: a success SnackBar with localized `idCopiedToClipboard` ("ID copied to clipboard", `app_localizations_en.dart:353`) appeared (`AppSnackBar.showSuccess(context, appL10n.idCopiedToClipboard)`, `profile_page.dart:305`).
- A5 (placeholder-leak guard): `pbpaste` NEVER equals `FlutterUIKitClient` (the V2TIM login placeholder) — a regression to `service.selfId` instead of `widget.userId`/`Prefs.getCurrentAccountToxId` would leak that. Same guard as S31 A14.
- A6: `[ProfilePage] Failed to copy Tox ID to clipboard` (`profile_page.dart:308`) MUST NOT appear in the log.
- A7: `official.get_runtime_errors({})` empty vs the Step-2 baseline.

## Notes
- L3-pin reason: cross-process clipboard contents are only ground-truthable on the host pasteboard (`pbpaste`); in-process `Clipboard.getData` is not faithful (UI_TEST_LAYERING §3).
- Key status (verified): `profileToxIdCopyButton` @ `profile_edit_fields.dart:304`; `profileToxIdSelectableText` @ `:340`. Both shipped. Copy handler `_copyToxId` @ `profile_page.dart:300-303` writes `widget.userId` as TEXT.
- Sibling distinction: S31 copies from BOTH ProfilePage (V1) and Settings (V2) and cross-checks they agree. S102 is the ProfilePage-button leg in isolation, framed as the keyed UI-tap upgrade of S31's V1 driver. S103 is the QR-image copy (a DIFFERENT clipboard type — image, not text).
- Gotcha: the copy path is SILENT on the happy path (no positive log markers); assertions are clipboard contents + SnackBar visibility + negative log markers.
- Linux: `xclip -o -selection clipboard` (X11) / `wl-paste` (Wayland). Windows: `powershell -Command Get-Clipboard`.
- Mobile parity: `_copyToxId` and `ProfileToxIdSection` are shared Dart (`lib/ui/profile/`, `lib/ui/profile_page.dart`) — identical on iOS/Android; only the host-pasteboard read command differs per platform.
