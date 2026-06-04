# S44 — Logout (退出登录)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on profileCrypt=plaintext network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because requires on-disk preservation diff (sha256) and SDK teardown observation
**Status**: covered

## Precondition
- One signed-in account A on HomePage; plaintext profile (no re-encrypt branch needed for Step 8 re-login).
- `current_account_tox_id` = toxA; `account_list` contains the single record.
- Pre-state snapshot for diff:
  ```bash
  sha256sum "$PROFILE" > /tmp/s44_profile_pre.sha
  find "$DATA" -type f -print0 | sort -z | xargs -0 sha256sum > /tmp/s44_data_pre.sha
  defaults read com.toxee.app 'flutter.account_list' > /tmp/s44_account_list_pre.json
  ```
- `MCP_BINDING=marionette`.

## Driver
1. Wait for `<nicknameA>\nOnline` (60s poll).
2. `marionette.tap({key: "sidebar_settings_tab"})`.
3. Tap `UiKeys.settingsLogoutButton` (`settings_logout_button`).
4. Confirmation `AlertDialog` mounts with title `Log Out`, body `Are you sure you want to log out?`, two `TextButton` actions (`Cancel` / error-tinted `Log Out`).
5. (Optional) Tap Cancel — verify no teardown fires, then re-tap Log Out button.
6. Tap confirm action via `UiKeys.settingsLogoutConfirmButton` (`settings_logout_confirm_button`).
7. After teardown completes (≤15s), poll snapshot up to 10s for LoginPage.
8. Re-login: tap account card via `login_page_account_card:<toxA>`; wait for HomePage `\nOnline` (≤30s).

## Assertions
- A2: post-confirm top route is LoginPage (`Saved Accounts` header + card with `<nicknameA>`); no HomePage sidebar tabs.
- A3: `defaults read com.toxee.app 'flutter.current_account_tox_id'` returns "does not exist".
- A5: `sha256sum` of `profiles/p_<toxA_prefix16>/tox_profile.tox` matches pre-state.
- A6: `find … | xargs sha256sum` on `account_data/<toxA>/` matches pre-state (chat history DB, file_recv, avatars preserved).
- A7: `account_list` Prefs entry unchanged.
- A9: log markers `[ToxAVService] shutdown() called` and `[FfiChatService] … dispose` fire; no `tim2tox_ffi_init_with_path` between Step 6 and Step 8.
- A10: Step 8 re-login lands on HomePage with `\nOnline` within 30s; markers `[ffi] tim2tox_ffi_init_with_path: using initPath=…/p_<toxA_prefix16>` and `HandleSelfConnectionStatus`.
- Negative grep (Step 6 → Step 8 window): `[AccountService] Failed to delete profile directory`, `Failed to delete account data directory`, `Prefs.removeAccount`, `teardown: service.dispose error`, `teardown: re-encrypt profile error` — must NOT appear.
- A8: no `Bad state: dispose was called` runtime errors.

## Notes
- `AppLocalizations.logOut` is reused as button label, dialog title, AND confirm action — the shipped `settings_logout_button` / `settings_logout_confirm_button` anchors keep the flow locale-stable.
- Ordering invariant: `Prefs.setCurrentAccountToxId(null)` must run AFTER `teardownCurrentSession` so `getSelfToxId()` check (account_service.dart:90) still resolves for the re-encrypt branch (if password set).
- `pushAndRemoveUntil` is load-bearing — replaced with `push` regresses to HomePage staying mounted under LoginPage with disposed-service stream errors.
- For encrypted-fixture variant (S44b deferred): additionally assert `head -c 8 "$PROFILE"` == `toxEsave` after Step 6.
- Hard kill between Step 3 and Step 6 leaves stale state; the `defaults read` A3 check catches this false-pass.
