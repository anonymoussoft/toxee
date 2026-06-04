# S2 — Login with saved account → HomePage

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=off profileCrypt=plain network=online`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned because the assertion is the live DHT bootstrap reaching Online (5-30s); L2 has no real network, so it can drive the tap but cannot observe the offline→online transition.
**Status**: covered (plaintext variant; encrypted variant S2b deviates on the password dialog only)

## Precondition
- One saved account A on disk (`profiles/p_<prefA16>/tox_profile.tox`).
- `autoLogin=off` for A — so the app lands on LoginPage with A's card, NOT auto-login (the `if (!autoLogin) return StartupShowLogin()` gate at `startup_session_use_case.dart:39-41`).
- `Prefs.nickname` may be set (LoginPage prefills it) but does not trigger auto-login while `autoLogin=off`.
- Plaintext profile → no password dialog (`Prefs.hasAccountPassword(toxId)` false in `_quickLogin`, `login_page.dart:278`). S2b: `profileCrypt=pwd:<pw>` surfaces `_showPasswordDialog` first.
- `network=online`, real DHT reachable.
- `MCP_BINDING=marionette`.

## Driver
1. `MCP_BINDING=marionette ./run_toxee.sh`; `URI=$(cat build/vm_service_uri.txt)`; `marionette.connect(uri=$URI)` + `arenukvern.fmt_connect_debug_app({mode:"uri", uri:$URI})`.
2. `fmt_semantic_snapshot` → assert `savedAccounts` header (`AppLocalizations.savedAccounts`) + A's account card present; LoginPage is showing, NOT a `\nOnline` sidebar.
3. Tap A's card via `marionette.tap({ key: "login_page_account_card:<toxA>" })`. Fallback only if key-driven tapping is unavailable: use `fmt_tap_widget(ref="s_N")` on the semantic ref matching A's nickname label.
4. **S2b only**: password dialog appears; `marionette.enter_text` (the field has no UiKey) then tap `ok` (`AppLocalizations.ok`).
5. Poll `fmt_semantic_snapshot` up to 60s for HomePage sidebar `_UserAvatar` showing `<nicknameA>` then `Online` (`statusOnline`, two `Text` nodes at `sidebar.dart:472-496`). Do NOT sleep — poll for the state change (DHT bootstrap is 5-30s).

## Assertions
- A1: Step 2 LoginPage shows `savedAccounts` header + exactly one card; no sidebar/`Online` node.
- A2: Log contains `[ffi] tim2tox_ffi_init_with_path: using initPath=…/p_<prefA16>` (FFI init fired only after the tap — autoLogin off skipped it at cold start).
- A3: Log contains `HandleSelfConnectionStatus: ENTRY` then `Notified self online status (userID=<toxA>…` (`V2TIMManagerImpl.cpp:5331+`).
- A4: HomePage renders — sidebar tabs `UiKeys.sidebarChats`, `UiKeys.sidebarContacts`, `UiKeys.sidebarApplications`, `UiKeys.sidebarSettings` (`sidebar.dart`).
- A5: Sidebar `_UserAvatar` shows `<nicknameA>` + `Online` within 60s.
- A6: `official.get_runtime_errors({})` baseline-clean; no `[LoginPage] Login boot failed` (`login_page.dart:456`) log line.

## Notes
- L3-pin reason: the Online transition is a real DHT handshake (`connectionStatusStream`, `main.dart:561` / `sidebar.dart:49`); L2 cannot reach it. The tap + LoginPage gating alone could be L2 — but the value assertion (A3/A5) is network-only, so the whole scenario pins to L3.
- Saved-account cards now expose `login_page_account_card:<toxId>` on the LoginPage tap target, so use the key before falling back to label/ref matching.
- Manual login (card tap) does NOT run `PlaceholderAccountMigration` the way auto-login does (`startup_session_use_case.dart:69` vs the best-effort stub in `login_use_case.dart:57`) — irrelevant for a clean Tox-ID account, but record any `FlutterUIKitClient` userID in the log as a deviation.
- `_busy` is held across boot+navigation (`login_page.dart:424`); a double-tap on the card cannot re-enter login.
- `defaults` cache: run `killall cfprefsd` before any shell read of Prefs.
