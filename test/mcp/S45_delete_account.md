# S45 — Delete account (注销账号)

**Layer**: L3 (MCP playbook)
**Fixture vector** (S45a): `accounts=2 current=A(encrypted+pwd) bystander=B(plaintext) autoLogin=on network=online history=non-empty`
**Fixture vector** (S45b): `accounts=1 current=A(plaintext, noPwd) autoLogin=on network=online history=non-empty`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because destroys on-disk profile/data + keychain verifier; requires multi-account isolation checks and `security` CLI
**Status**: covered (S45a + S45b); S45c/d/f deferred

## Precondition
- **S45a**: A logged in with password `P_DELETE` (encrypted profile, `flutter_secure_storage` `<toxA>_password_hash` + `_salt` set); bystander B exists on disk (plaintext, no verifier). Both `account_data/<prefix>/chat_history/` non-empty so SQLite cleanup is exercised.
- **S45b**: A is the only account, plaintext, no password, no verifier.
- Pre-state snapshot:
  ```bash
  ls -1 "$SUPPORT/profiles" | sort > /tmp/s45_profiles_before.txt
  ls -1 "$SUPPORT/account_data" | sort > /tmp/s45_account_data_before.txt
  ```
- `MCP_BINDING=marionette`.

## Driver
1. Wait for `<nicknameA>\nOnline` (60s poll).
2. `marionette.tap({key: "sidebar_settings_tab"})`.
3. Tap `Delete Account` button (proposed `settings_delete_account_button`).
4. Dialog mounts (proposed `settings_delete_account_dialog`):
   - **S45a (hasPassword)**: obscured `TextField` (proposed `settings_delete_account_password_input`); no word challenge.
   - **S45b (no password)**: bold `SelectableText` with a random word from `_kDeleteConfirmWords` (settings_page.dart:44-48 — 19-word list) + plain `TextField` (proposed `settings_delete_account_word_input`). **Must parse the displayed word from snapshot** — Random-picked at dialog open.
5. Enter password (`P_DELETE`) OR displayed word (case-insensitive after trim).
6. Tap destructive `Delete` action (proposed `settings_delete_account_submit_button`; label `AppLocalizations.delete`, not `deleteAccount`; error-tinted foreground).
7. Loading `CircularProgressIndicator` dialog mounts. Poll snapshot ≤60s until LoginPage appears.

## Assertions
- A4: dialog renders password input XOR word-challenge, not both.
- A5: displayed word ∈ `_kDeleteConfirmWords` (regex match against 19-word list).
- A6: submit transitions to loading dialog (ProgressIndicator).
- A8: post-delete UI is LoginPage (S45a: B's card still present, A absent; S45b: empty-state CTAs).
- **A11**: `[ -e "$profile_dir_a" ]` is false.
- **A12**: `[ -e "$data_dir_a" ]` is false.
- **A13 (S45a)**: `[ -e "$profile_dir_b" ]` and `[ -e "$data_dir_b" ]` true — bystander untouched.
- **A14**: `security find-generic-password -s flutter_secure_storage -a "${TOXA}_password_hash"` returns non-zero (verifier removed).
- A15 (S45a): B's secure-storage state unchanged.
- A16: `defaults read com.toxee.app 'flutter.account_list' | grep "${TOXA:0:16}"` returns nothing.
- A17 (Prefs pointer state — grouped per variant; the wire key is snake_case `current_account_tox_id`, see `lib/util/prefs.dart:62`):
  - **S45a**: `defaults read com.toxee.app 'flutter.current_account_tox_id'` returns non-zero (the pointer is cleared — no implicit successor account).
  - **S45b**: `defaults read com.toxee.app 'flutter.current_account_tox_id'` returns non-zero (the only account was deleted; pointer cleared).
- A19: no `tencent_cloud_chat_failed_messages.*${TOXA:0:16}` Prefs remain.
- A20 (S45b, optional Step 13): cold relaunch lands on empty LoginPage; no `StartupShowError` / `Profile not found` in log.
- Negative log grep: `clearAllAccountData before teardown failed`, `Failed to delete profile directory`, `Failed to delete account data directory`, `teardown: service.dispose error`, `teardown: re-encrypt profile error` must NOT appear. `re-encrypt profile error` is especially load-bearing — `deleteAccountCompletely` passes `reEncryptProfile: false` and that branch must not run.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- Ordering invariant: `service.clearAllAccountData()` runs **before** `teardownCurrentSession(reEncryptProfile: false)` so SQLite file locks release while service is live. Reversing this orphans WAL files.
- `reEncryptProfile: false` is critical: re-encrypting a file about to be unlinked is wasted I/O, and a failure there would short-circuit the `Directory.delete`.
- `confirmWord` is `Random().nextInt`-picked at every dialog open — never hardcode `"delete"` (1/19 chance). Use proposed `settings_delete_account_word_challenge_label` key on the bold `SelectableText` for programmatic readout.
- Recommended positive log marker (additive source change): `AppLogger.log('[AccountService] deleteAccountCompletely(toxId=…) ok')` at end of success path — flips §7 from "absence of negative" to "presence of positive".
- S45c (wrong password/word): typed wrong → `invalidPassword` SnackBar / `deleteAccountWrongWord`, dialog stays open. Deferred.
- S45d (cancel): tap Cancel — dialog dismisses, no teardown. Deferred.
- S45f (delete from LoginPage via `_confirmDeleteAccountFromLoginPage`): different code path, hardcoded lowercase `"delete"` word, no random pick. Deferred separate playbook.
- macOS `SharedPreferences` writes flush asynchronously — allow ≤5s slack after LoginPage paint before `defaults read` assertions.
- A21 (`SessionPasswordStore` cleared) observable only from inside isolate — track as follow-up.
