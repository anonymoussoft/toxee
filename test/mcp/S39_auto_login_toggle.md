# S39 — Auto-login toggle (off → restart → LoginPage)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=true(default) profileCrypt=plaintext network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because requires cold-restart cycles + on-disk Prefs verification
**Status**: covered (S39a is PR-gate cheap; S39b/c/d optional in full suite)

## Precondition
- One signed-in account A; `acct_auto_login_<toxA_prefix16>` unset (default true).
- Plaintext profile (no password prompt during S39b re-login).
- `currentAccountToxId` set to toxA; `account_list` contains the single record.
- `MCP_BINDING=marionette`.
- Pre-test: `defaults delete com.toxee.app 'flutter.acct_auto_login_<prefix16>'; killall cfprefsd`.

## Driver
**S39a — Toggle off → relaunch → LoginPage**
1. Wait for `<nicknameA>\nOnline` (60s poll). Verify `autologin_value` shell helper returns `(unset)` or `true`.
2. `marionette.tap({key: "sidebar_settings_tab"})`.
3. Tap `UiKeys.settingsAutoLoginSwitch` (`settings_auto_login_switch`).
4. Verify Switch state flips to `selected: false`; `autologin_value` shell helper returns `false`.
5. Graceful quit: `osascript -e 'quit app "Toxee"'`. Relaunch via `./run_toxee.sh`; reconnect MCP.
6. Snapshot must show `Saved Accounts` header + keyed card `login_page_account_card:<toxA>` with `<nicknameA>`; must NOT show `\nOnline` sidebar.

**S39b** — On LoginPage, tap account card via `login_page_account_card:<toxA>`; wait for HomePage `\nOnline`. Verify `autologin_value` still `false`.

**S39c** — On HomePage, re-enter Settings; verify Switch still off.

**S39d** — Toggle Switch on; quit; relaunch; verify direct HomePage (no LoginPage); `autologin_value` returns `true`.

## Assertions
- A1: pre-state `acct_auto_login_<prefix16>` is `(unset)` or `true`.
- A4: after toggle off, `defaults read` returns `false` (per-account scoped key).
- A6: relaunch lands on LoginPage (`Saved Accounts` header present, `login_page_account_card:<toxA>` present, no `\nOnline`).
- **A7 (critical)**: relaunch log window does NOT contain `[ffi] tim2tox_ffi_init_with_path`, `[FfiChatService] login(`, `HandleSelfConnectionStatus`, `encryptProfileFile`, `decryptProfileFile` — autoLogin off must skip FFI entirely.
- A9: post-manual-login `autologin_value` still `false` (manual login must NOT silently reset).
- A12: after toggle on + relaunch, lands directly on HomePage with `\nOnline`; relaunch log contains `tim2tox_ffi_init_with_path` and `HandleSelfConnectionStatus`.
- A10: Switch state survives login transition.
- A14 (optional, multi-account fixture): toxB's `acct_auto_login_<toxB_prefix16>` unchanged.
- `official.get_runtime_errors({})` returns baseline.

## Notes
- Scoped key precedence: `getAutoLogin(toxId)` reads `acct_auto_login_<toxIdPrefix16>` first, falls back to legacy `auto_login` when toxId null. Test must set `currentAccountToxId` so the per-account path is exercised.
- Shell helper:
  ```bash
  autologin_value() {
    killall cfprefsd 2>/dev/null
    local raw=$(defaults read com.toxee.app "acct_auto_login_${PREFIX16}" 2>/dev/null)
    case "$raw" in "") echo "(unset)";; 1) echo "true";; 0) echo "false";; *) echo "$raw";; esac
  }
  ```
- macOS `defaults read` outputs `0` / `1` for bools; cfprefsd caching can return stale values without `killall`.
- If toxA has a password (shared S40 fixture), Step 8 surfaces password dialog — record deviation; S39 semantics are gate-correctness, not no-password login.
- `_setAutoLogin` is fire-and-forget; sleep 1s before quit (Step 5) to avoid losing the write.
- S39a alone is a ~50s PR-gate smoke; full a–d ~3 min.
