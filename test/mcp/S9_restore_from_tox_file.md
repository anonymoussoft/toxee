# S9 — Restore from .tox file (native picker path)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=0-or-1 current=none autoLogin=off network=online profileCrypt=plain-or-pwd:<pw> staged-tox-file=present`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the macOS native file picker cannot be MCP-driven (§7b). L3 can hand-stage the `.tox` on disk + drive the `filePathOverride` seam; L2 still can't reach HomePage without DHT-online for the post-tap connection assertion.
**Status**: covered (S9a plaintext + S9b encrypted)

## Precondition
- Zero saved accounts (or one unrelated account, `autoLogin=false`) so app lands on LoginPage.
- `Prefs.account_list`, `currentAccountToxId`, `nickname` clean for the import-target toxId (no duplicate; restore aborts on `accountAlreadyExists`).
- Staged file at `/tmp/toxee_test/restore.tox`:
  - **S9a**: plaintext `.tox` blob (first 8 bytes NOT `toxEsave`).
  - **S9b**: encrypted `.tox` blob (first 8 bytes ARE `toxEsave`), password known.
- No `profiles/p_<toxId_prefix16>/` for the import target yet.
- `MCP_BINDING=marionette`.

## Driver
1. `fmt_semantic_snapshot` → assert LoginPage shows the `loginPageRestoreFromToxFile` action (`AppLocalizations.restoreFromToxFile`). Save `s9_before.png`.
2. Drive the picker via the test seam — native picker cannot be tapped (§7b). Call the debug-only MCP tool that invokes `LoginPageController.restoreFromToxFile(filePathOverride: "/tmp/toxee_test/restore.tox")` (the `@visibleForTesting` param at `login_page_controller.dart:332`). Plain `marionette.tap({ key: "login_page_restore_from_tox_file" })` only verifies the affordance fires the OS picker; it cannot select a file.
3. **S9b only**: when the password dialog mounts (`_showPasswordDialog`, `login_page.dart:173`, prompt `enterPasswordToImport`), enter the password and confirm. Wrong password → retry loop (`login_page.dart:526-529`).
4. Poll snapshot ≤15s for the success SnackBar with `restoreFromToxFileSuccess(<nickname>)` text; confirm the saved-accounts list gained the restored card.
5. Tap the restored account card to sign in; poll snapshot ≤60s for HomePage sidebar `_UserAvatar` label `<nickname>\nOnline`. Save `s9_after.png`.

## Assertions
- A1: LoginPage shows `loginPageRestoreFromToxFile` before any tap.
- A2: Post-Step 2/3, `account_list` JSON contains a record with the restored `toxId` and `nickname` (= embedded nickname, else `importedAccountDefaultName`), `autoLogin=false` (`login_page_controller.dart:413-420`).
- A3: `profiles/p_<toxId_prefix16>/tox_profile.tox` exists, non-empty (written at `login_page_controller.dart:408-409`).
- A4: Success SnackBar text == `restoreFromToxFileSuccess(<nickname>)`.
- A5 (S9b): `security find-generic-password -s flutter_secure_storage -a "<toxId>_password_hash"` succeeds (set via `_setAccountPasswordFn`, `login_page_controller.dart:421-422`).
- A6: After Step 5, sidebar `_UserAvatar` label is `<nickname>\nOnline`; log has `HandleSelfConnectionStatus: Notified self online status (userID=<toxId>…`.
- A7: No `[LoginPageController] Restore failed` and no `rollback:` log lines (`login_page_controller.dart:433`, `438-468`).
- A8 (negative): re-running with the same file yields `accountAlreadyExists` (`login_page_controller.dart:394-397`), NOT a second profile dir.
- A9: `get_runtime_errors({})` baseline-clean.

## Notes
- **L3-pin reason**: native macOS file picker (`file_picker`) is undriveable by MCP — §7b mandates test-overriding the `FilePicker.platform.pickFiles(...)` call at `login_page_controller.dart:340-343` via the `filePathOverride` seam, gated debug-only.
- S9a/S9b differ only in the staged blob + the `_showPasswordDialog` branch; on decrypt failure with a supplied password the controller returns `invalidPassword` (`login_page_controller.dart:369-377`), and the UI loops for retry.
- Restore only adds + selects the account; it does NOT auto-login (`autoLogin=false`) — Step 5's card tap is the actual sign-in.
- Reset between runs: `rm -rf profiles/p_<toxId_prefix16>/`; `defaults delete com.toxee.app 'flutter.account_list'` entry for the toxId; `killall cfprefsd` before shell reads of Prefs.
