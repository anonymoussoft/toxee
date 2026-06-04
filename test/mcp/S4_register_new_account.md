# S4 — Register new account

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=0-or-1 current=unset autoLogin=off network=online sessionPwd=none-or-set profileCrypt=plaintext-or-encrypted`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because requires real Tox identity generation + on-disk profile creation + keychain (S4b) writes
**Status**: covered (S4a + S4b)

## Precondition
- Fixture B0 (no profiles) or B1 (one pre-existing plaintext account, `autoLogin=false`, distinct nickname)
- `~/Library/Containers/com.toxee.app/Data/Library/Application Support/com.toxee.app/profiles/` exists and is empty (B0) or contains one `p_<prefix16>/`
- Prefs `account_list`, `current_account_tox_id`, `nickname` cleared (B0)
- `FeatureFlags.enableFirstRunBackupWizard=false` in fixture (or be ready to dismiss wizard)
- `MCP_BINDING=marionette`

## Driver
1. `fmt_semantic_snapshot` → assert `LoginPage` shows `Register new account` action card (`AppLocalizations.registerNewAccount`)
2. Tap the `Register new account` card (fallback: semantic-label match — no `loginPageRegisterNewAccount` key today)
3. Snapshot → assert AppBar title `Register new account` and form with nickname/status/password/confirm fields
4. `marionette.enter_text` on `UiKeys.registerPageNicknameField` (`register_page_nickname_field`) with `S4_Tester` (≤12 display units)
5. **S4a**: leave `registerPagePasswordField` + `registerPageConfirmPasswordField` blank
   **S4b**: type `S4_pw_test` into both `register_page_password_field` + `register_page_confirm_password_field`
6. Tap `UiKeys.registerPageRegisterButton` (`register_page_register_button`)
7. Poll snapshot up to 60s for sidebar `_UserAvatar` label to show `<nickname>\nOnline`

## Assertions
- Log contains `[ffi] tim2tox_ffi_init_with_path: using initPath=.../.tmp_register_` then `using initPath=.../p_<NEW_PREFIX>` (the temp→final rename)
- Log contains `HandleSelfConnectionStatus: Notified self online status (userID=<NEW_TOXID>` (64-hex)
- `…/profiles/p_<NEW_PREFIX>/tox_profile.tox` exists, non-empty
- Prefs `account_list` JSON contains a record with `toxId=<NEW_TOXID>` and `nickname=S4_Tester` (or `S4_Tester_Pw`)
- Prefs `current_account_tox_id` == `<NEW_TOXID>`; Prefs `nickname` == registered nickname
- First 8 bytes of `tox_profile.tox` are NOT `toxEsave` while session is live (plaintext-at-rest invariant)
- Sidebar `_UserAvatar` shows `<nickname>\nOnline` within 60s
- No `Account with this nickname already exists` or `Failed to generate Tox ID` in log
- No leftover `…/profiles/.tmp_register_*` directory after success
- **S4b only**: `security find-generic-password -s flutter_secure_storage -a "<NEW_TOXID>_password_hash"` succeeds; same for `_password_salt`
- **S4b optional (encrypt-at-teardown)**: after `osascript -e 'quit app "Toxee"'` + 3s, first 8 bytes of `tox_profile.tox` ARE `toxEsave`

## Notes
- `selfId` must NOT be used as the persisted toxId — only `getSelfToxId()` (see `account_service.dart:409-419`); leaks `FlutterUIKitClient` otherwise.
- Two `FfiChatService` instances are created: temp-dir for ID discovery then `_createAccountScopedService` for the real session — don't assert object identity.
- `defaults` cache: run `killall cfprefsd` between in-app write and shell read of Prefs.
- If `enableFirstRunBackupWizard=true`, S4 needs to drive past the wizard before HomePage; prefer the fixture toggle.
