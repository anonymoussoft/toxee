# S71 — Import-then-auto-switch (LoginPage `.tox` restore)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2 current=none autoLogin=off network=online sessionPwd=clean staged-tox-file=present`
**Harness mode**: peerHarness=none
**Promotion target**: L3-pinned — needs native file picker bypass (debug-only `mcp_toolkit` tool or `@visibleForTesting` shim) plus DHT-online for the post-switch sidebar assertion.
**Status**: covered with Plan B (debug-only `toxee_restore_from_tox` MCP tool); plaintext `.tox` variant.

## Precondition
- Two saved accounts A and B on disk (`profiles/p_<prefA16>/tox_profile.tox`, `profiles/p_<prefB16>/tox_profile.tox`), plaintext, NOT active.
- `account_list` JSON has A and B records only; C (import target) is the surprise.
- Staging file at `/tmp/toxee_test/test_account.tox` — Account C's plaintext `.tox` blob, NOT in `account_list`, NOT under `profiles/`.
- `Prefs.nickname`, `statusMessage`, `avatarPath`, `currentAccountToxId` all cleared/empty.
- `autoLogin=false` so app lands on LoginPage.
- `MCP_BINDING=marionette`.

## Driver
1. Snapshot LoginPage; confirm keyed cards `login_page_account_card:<toxA>` and `login_page_account_card:<toxB>` plus the visible labels (`H\nhehe2\n…`, `O\nOriginal B\n…`) and `loginPageRestoreFromToxFile` action. Save `s71_before.png`.
2. `marionette.tap({ key: "login_page_restore_from_tox_file" })` — file picker opens.
3. Drive the picker via debug-only seam: `fmt_client_tool({ name: "toxee_restore_from_tox", input: { filePath: "/tmp/toxee_test/test_account.tox", password: "" } })`. (Fallback Plan A: `LoginPageState.debugRestoreFromToxFileForTest(filePath: ...)`. Plan C AppleScript only as last resort.)
4. Poll snapshot ≤15s for SnackBar with `restoreFromToxFileSuccess` text (`Restored account: <TEST_TOX_NICKNAME>`); confirm saved-accounts list now shows 3 cards.
5. Tap the new C card via `marionette.tap({ key: "login_page_account_card:<toxC>" })`. Fallback only if key-driven tapping is unavailable: use `fmt_tap_widget` on the semantic ref for the new card.
6. Poll snapshot ≤60s for HomePage with sidebar `_UserAvatar` label starting with `TEST_TOX_NICKNAME\n…`. Save `s71_after.png`.

## Assertions
- A1: Step 1 LoginPage has exactly 2 saved-account cards, addressable via `login_page_account_card:<toxA>` and `login_page_account_card:<toxB>`.
- A2: Pre-import, `defaults read com.toxee.app 'flutter.nickname'` returns empty/missing.
- A3: Post-Step 4, `account_list` JSON contains 3 entries including `TEST_TOX_ID`.
- A4: `profiles/p_<toxC_prefix16>/tox_profile.tox` exists post-Step 4.
- A5: Sidebar `_UserAvatar` label starts with `TEST_TOX_NICKNAME` after Step 6.
- **A6 (the fix)**: `defaults read com.toxee.app 'flutter.nickname'` == `TEST_TOX_NICKNAME`.
- **A7 (the fix)**: `defaults read com.toxee.app 'flutter.statusMessage'` matches embedded value (likely empty).
- **A8 (the fix)**: `defaults read com.toxee.app 'flutter.avatarPath'` matches the per-account avatarPath for C (likely absent).
- A9: `defaults read com.toxee.app 'flutter.currentAccountToxId'` == `TEST_TOX_ID`.
- A10: Log contains `[ffi] tim2tox_ffi_init_with_path: using initPath=…/p_<toxC_prefix16>` AND `HandleSelfConnectionStatus: Notified self online status (userID=<toxC>…)`.
- A11: `get_runtime_errors({})` baseline-clean.
- A12: No `[LoginPageController] Restore failed` or `rollback:` log lines.
- Negative log: no `Notified self online status (userID=<toxA_prefix>` or `<toxB_prefix>` after import-and-tap.

## Notes
- Echo peer harness intentionally not used — this scenario tests multi-account portability on a single toxee instance, no second peer required.
- **A6 is the primary regression assertion** — guards the 2026-05-28 fix at `account_service.dart:248-290` that mirrors `nickname`/`statusMessage`/`avatarPath` into global Prefs on successful `initializeServiceForAccount`.
- File picker bypass is mandatory; native picker cannot be MCP-driven. Recommended path: register debug-only `MCPCallEntry.tool` named `toxee_restore_from_tox` in `login_page.dart` `initState` gated on `kDebugMode && MCP_BINDING != ''`.
- Encrypted-file sub-variant (S71b) extends the picker tool with a `password` parameter and drives `_showPasswordDialog`.
- Cross-reference fix paths: `account_service.dart:162-172,248-290`, `account_switcher.dart` (same propagation on in-app switch — S3), `login_page_controller.dart:restoreFromToxFile` (line 329, exposes `filePathOverride`).
- Reset between runs: `defaults delete com.toxee.app 'flutter.nickname' statusMessage avatarPath currentAccountToxId`; `rm -rf profiles/p_<toxC_prefix16>/ account_data/<toxC>/`; ensure `account_list` JSON has only A and B.
