# S103 — Self-profile: QR section copy / action

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=any (Offline OK)`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the QR copy writes a PNG to the OS **image** pasteboard (`ImageClipboard().copyImage`, cross-process — UI_TEST_LAYERING §3 "OS clipboard cross-process verification → L3 only"), and the QR render is a `FutureBuilder<String>` over a generated image file on disk (real `path_provider`, never L1). The button-fires-`onCopy(qrPath)` wiring alone could be an L1 callback probe.
**Status**: covered (L1 WidgetTester real-UI gate — test/ui/profile_qr_copy_real_ui_test.dart). The L1 gate pumps the REAL `ProfilePage` (isEditable), reaches into the REAL `ProfileQrSection` it built — whose `onCopy` IS the bound production `_copyQrImage` (`profile_page.dart:493`) — and invokes it, running the production copy handler end-to-end against a mocked `image_clipboard` channel (NOT a re-implemented test closure, so a regression inside `_copyQrImage` fails the gate). The gate asserts: (A1) `ProfileQrSection.enableCopy` matches the production platform gate (`profile_page.dart:494` — on macOS/Windows, off on Android/iOS/Linux), so it is host-portable incl. Linux CI; (A2) the `image_clipboard` channel received `copyImage` with the path passed to `_copyQrImage`; (honesty caveat) NO `Clipboard.setData` text write occurred; (A3) the success snackbar appeared. The literal `profileQrCopyButton` hit-test needs the QR `FutureBuilder` to resolve (real canvas→PNG→temp-file image-gen), so it — plus the cross-process image-pasteboard verification (`osascript 'clipboard info'`) — stays L3. **There is NO data-half `l3_*` gate for the QR copy** (the copied artifact is a PNG, not a `l3_dump_state` field).
**Covered-by**: test/ui/profile_qr_copy_real_ui_test.dart
**Mobile-parity**: `_copyQrImage` and `ProfileQrSection` are shared Dart (`lib/ui/profile/profile_qr_section.dart`, `lib/ui/profile_page.dart`). The `image_clipboard` plugin supports iOS/Android; the same `copyImage` MethodChannel call is made on all platforms. This L1 gate covers all targets; only the host-side image-clipboard verification command differs per platform (`osascript 'clipboard info'` on macOS, platform-specific image-clipboard API on others).

> **Honesty caveat (corrects a common assumption): the QR copy button does NOT put the tox-id/URI text on the clipboard.** `UiKeys.profileQrCopyButton` calls `onCopy(qrPath)` (`profile_qr_section.dart:129`), wired to `_copyQrImage` (`profile_page.dart:493` → `:287-290`), which calls `ImageClipboard().copyImage(path)` (`package:image_clipboard/image_clipboard.dart`). It copies the rendered QR **image file**, so a plain-text `pbpaste` will be EMPTY / unchanged. The tox-id TEXT copy is a separate button — `profile_tox_id_copy_button` (S102). Both buttons share the same `idCopiedToClipboard` ("ID copied to clipboard") snackbar string, which is misleading for the QR leg but is the shipped behavior.

## Precondition
- Account A signed in, plaintext profile; self-profile reachable via `sidebarUserAvatar`.
- `ProfilePage` is built with `isEditable: true` and the QR section copy enabled — `ProfileQrSection(enableCopy: true, …)` is the default; the copy button only renders inside `if (enableCopy)` (`profile_qr_section.dart:122`). On peer (non-editable) profiles copy is disabled; this is the SELF profile so it's on.
- The QR image generates successfully — `qrFuture` resolves to a file path; the copy button only mounts in the `ConnectionState.done && hasData && !hasError` branch (`profile_qr_section.dart:54-73`). Allow up to ~3s for the QR render (the `FutureBuilder` shows a `CircularProgressIndicator` until done — this is why `pumpAndSettle` never settles on this page).
- macOS pasteboard pre-cleared for both text AND image (`pbcopy </dev/null`; the image leg is read via the AppleScript below, not `pbpaste`).
- `MCP_BINDING=marionette`.

## UI Driver
1. `marionette.tap` `UiKeys.sidebarUserAvatar` (`sidebar_user_avatar`, `sidebar.dart:400`) → `ProfilePage` mounts.
2. Poll the snapshot ≤3s for the QR section to finish rendering — the `Image.file` + the two action buttons (`saveImage` + the copy button) appear once `qrFuture` resolves. (No key on the QR `Image` itself; assert via the labelled `saveImage`/`copy` buttons being present and the `profile_tox_id_selectable_text` label co-present, since both live in the same `ProfilePage` body.)
3. `marionette.tap` `UiKeys.profileQrCopyButton` (`profile_qr_copy_button`, `profile_qr_section.dart:125`) — the `OutlinedButton.icon` whose `onPressed: () => onCopy(qrPath)`.
4. Capture the SnackBar within ~1s (auto-dismisses ~4s).
5. Verify the OS **image** clipboard (NOT `pbpaste`): see A2.

## Assertions
- A1: after Step 2, the QR copy button (`profile_qr_copy_button`) is present and tappable in the snapshot (proves the `enableCopy` + `hasData` branch rendered, i.e. the QR generated). The `profile_tox_id_selectable_text` label (the full 76-hex id) is co-present in the same ProfilePage body (snapshot presence — the QR render itself has no `l3_dump_state` field, so the selectable-text label is the assertable identity anchor).
- A2 (primary, image clipboard): after Step 3, the macOS pasteboard holds a PNG/TIFF image, NOT text. Verify with:
  ```bash
  osascript -e 'clipboard info' | grep -iE 'PNG|TIFF|picture' && echo OK_IMG || echo FAIL_IMG
  pbpaste | wc -c   # expected ~0 — the QR copy does NOT write text
  ```
  An image type present (and `pbpaste` empty) is the proof the QR-image copy fired. If a future change switches the QR button to copy a `tox:` URI as TEXT, this assertion must be rewritten to a `pbpaste` URI match — flag it then.
- A3: a success SnackBar with localized `idCopiedToClipboard` ("ID copied to clipboard", `app_localizations_en.dart:353`) appeared (`AppSnackBar.showSuccess`, `profile_page.dart:292`). NOTE: the string says "ID" but the artifact is the QR image — see the honesty caveat.
- A4: the QR copy-error path `appL10n.copyFailed(...)` (`profile_page.dart:296`) MUST NOT surface (no error SnackBar).
- A5: `official.get_runtime_errors({})` empty vs the Step-1 baseline (catches a QR `FutureBuilder` / `Image.file` exception).

## Notes
- L3-pin reason: image-pasteboard write is cross-process (UI_TEST_LAYERING §3) AND the QR render needs real `path_provider` disk I/O; neither is L1-expressible. No `l3_*` data-half gate exists because the copied artifact is a PNG, not a dump-state field.
- Key status (verified): `profileQrCopyButton` @ `profile_qr_section.dart:125`; copy handler `_copyQrImage` @ `profile_page.dart:287-290` (uses `ImageClipboard().copyImage`, import @ `profile_page.dart:7`).
- Sibling distinction: S102/S31 copy the tox-id as TEXT (`Clipboard.setData`, `pbpaste`-verifiable). S103 copies the QR PNG as an IMAGE (`ImageClipboard`, AppleScript-verifiable). Different clipboard channel — do NOT assert S103 via `pbpaste` text equality.
- Gotcha: the page's QR `FutureBuilder` shows a perpetual `CircularProgressIndicator` until the image resolves; `pumpAndSettle` hangs (documented in `profile_edit_persists_to_account_list_test.dart:96-104`). Poll, don't settle.
- Mobile parity: `_copyQrImage` + `ProfileQrSection` are shared Dart (`lib/ui/profile/`, `lib/ui/profile_page.dart`); the `image_clipboard` plugin supports iOS/Android, so behavior is identical — only the host-side image-clipboard verification command differs per platform.
