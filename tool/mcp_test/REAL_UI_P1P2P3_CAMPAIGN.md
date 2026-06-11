# Real-UI P1/P2/P3 campaign — 2026-06-10 (RECOVERY ANCHOR)

> Durable state for the P1/P2/P3 development campaign (user directive 2026-06-10:
> 在 master 串行开发 P1/P2/P3). Any session can resume from this file. Update the
> per-batch Status + the Batch log as work proceeds; commit after every batch.
> Case rationale/specs live in `doc/research/REAL_APP_UI_TEST_INVENTORY.md`
> (§P1 17 cases / §P2 8 items / §P3); this file owns EXECUTION state only.

## Mission

Implement, serially on master:
- **P1**: 17 new real-app real-widget scenarios (no production change expected;
  tiny automation-only keys allowed where verify-first reading shows a keyless
  load-bearing surface — precedented).
- **P2**: 8 seam/key-gated items (fork keys, l3 seed seam, `ui_long_press`,
  presence-dot semantics, 3 verify-first investigations).
- **P3**: the writable subset (perf burst variant, ar/RTL verify-first,
  platform run plan); platform RUNS (iOS/Android/Win11) are run-phase tasks.

## HARD CONSTRAINTS (this campaign)

1. **WRITE-PHASE FIRST.** Write all batches with hermetic verification only;
   the run phase comes after the write phase closes (campaign-proven protocol).
   ~~Parallel-session hot-file rules~~ — LIFTED 2026-06-10: the user cancelled
   the parallel run session and granted full file access ("已经取消并行会话，
   你可以对所有文件做修改和重写"). All files editable; its coherent toxee-side
   WIP was archived (see Batch log); its tim2tox-submodule native WIP
   (`ffi/dart_compat_friendship.cpp`, uncommitted) is left in place for the
   run-phase owner — do not revert, do not commit blind.
2. Commit per batch with EXPLICIT file adds (never `git add -A`; the tree may
   hold run artifacts like `*.png` and the dirty tim2tox submodule).
3. Standing rules apply: real-UI first (l3 only for seeding/navigation-stability,
   never the asserted action); verify-first by READING current code (don't trust
   doc conclusions); soft-skip with evidence; deep root-cause fixes; mobile
   parity noted per change; codex review per batch (telemetry-off:
   `env -u OTEL_EXPORTER_OTLP_ENDPOINT codex exec -c otel.exporter=none
   -c otel.log_user_prompt=false …`).

## Per-batch contract (every batch MUST)

1. Read this file + `doc/research/REAL_APP_UI_TEST_INVENTORY.md` (its case row)
   + `tool/mcp_test/REAL_UI_TWO_PROCESS.md` + the files in the File map below.
2. New scenarios live in a NEW part file (`drive_real_ui_pair_p1_*.dart` /
   `_p2_*.dart`), declared in `drive_real_ui_pair.dart`'s part list, dispatched
   per-case + as a `sweep_<batch>` chain (per-case `[sweep] <case>: PASS|FAIL|
   SKIP(<reason>)` + final counts; exit non-zero if any hard case fails; exit 75
   = SKIP for individual dispatch), registered in `_validRealUiScenarios` +
   `_requiredRealUiState` + `_resultRealUiState` + a `rui-p1-*` campaign.
3. Gates (all green before commit): `flutter analyze lib tool --no-fatal-warnings
   --no-fatal-infos` 0 NEW issues; `dart run tool/mcp_test/fixture_c_unified_runner.dart
   --plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0;
   `--list-real-ui-campaigns` shows the new campaign; driver
   `--self-test-shell-recovery` PASS; touched hermetic tests pass;
   `dart run tool/mcp_test/gen_scenario_index.dart --check` green.
4. Codex review; apply findings; update this file's Status + Batch log;
   `git commit` (message: `test(real-ui): p1p2p3 batch <N> — <domain> (written, unrun)`).
5. Do NOT update `test/mcp/S*.md` headers to claim coverage — written-unrun
   scenarios are not validated gates yet; header updates happen in the run phase.

## Batches

### Batch I — `ui_long_press` primitive (prereq for P1 #8 + mobile-trigger parity)

`lib/ui/testing/ui_drive_tools.dart`: `ui_long_press` {key?|x,y?, holdMs?} —
real touch PointerDown → await hold (default 600 ms > kLongPressTimeout) →
PointerUp through `GestureBinding.handlePointerEvent`. Register in
`registerUiDriveToolsIfDebug()`. Hermetic gates in
`test/ui/testing/ui_drive_tools_test.dart`: onLongPress fires once (and onTap
does NOT); offstage/absent key errors. FakeAsync note: test starts the handler
future un-awaited, `tester.pump(700ms)` advances fake time, then awaits it.
**STATUS: DONE** (registered as the 5th ui_drive tool; hermetic gates 8/8 incl.
3 new long-press cases; analyze 0-new; codex round found P1 stale-comment +
P2 pump-pattern doc drift — both fixed).

### Batch II — P1 single-instance quintet (`drive_real_ui_pair_p1_single.dart`)

| case | inventory row | verify-first reading needed |
|---|---|---|
| `account_card_management_menu` | P1#8 | login_page.dart: card long-press/secondary trigger? menu surface keys? uses `ui_long_press` |
| `account_delete_full_flow` | P1#9 | settings 注销 flow keys + confirm dialog; throwaway account via real RegisterPage |
| `settings_switch_account_entry` | P1#10 | settings switch-account entry key → login cards → switch back |
| `conference_rename_leave` | P1#11 | reuse batch-7 helpers for AVChatRoom create; rename + leave confirm-by-label |
| `zh_locale_page_walk` | P1#12 | per-page zh labels (外观 etc.); revert-to-en discipline (batch-1 locale finding) |

Sweep `sweep_p1_single` · campaign `rui-p1-single` · state no-friend→no-friend.
**STATUS: DONE** (5/5 WRITTEN; new part ~700 LOC + runner/dispatch entries;
analyze 0-new; planner/validate/campaign-list/self-test/INDEX green; codex
round-1 found 3 P1 — zh-walk locale-leak guard on early-FAIL, switch-entry
false-PASS without account #2 → now registers RuiP1SwB via real RegisterPage
once + asserts toxId actually flips, delete-flow now ENDS the sweep (account #2
deleted, primary re-entered) — all applied; round-2 confirmed)

### Batch III — P1 two-process chat/conv octet (`drive_real_ui_pair_p1_chat.dart`)

| case | inventory row | verify-first reading needed |
|---|---|---|
| `chat_recall_message` | P1#3 | fork menu: recall item on fresh self msg; revoke path in bridge (stub? → honest scope) |
| `read_receipt_double_tick` | P1#4 | read-status icon keyed? (likely needs automation-only fork key) |
| `forward_to_group_target` | P1#5 | batch-7 group helpers + S17 picker keys |
| `draft_restore_on_conv_switch` | P1#6 | does the fork write/restore drafts? (DartSetConversationDraft exists natively) |
| `typing_indicator_render` | P1#7 | does any UI surface render typing? (fixture_c_typing = data half) |
| `unread_badge_total_sidebar` | P1#13 | sidebar Chats badge key/text |
| `search_empty_state` | P1#14 | custom_search empty-state marker |
| `image_preview_open_hardened` | P1#16 | bounded retry-tap; honest best-effort fallback |

Sweep `sweep_p1_chat` · campaign `rui-p1-chat` · friends→friends. **STATUS: DONE**
(8/8 WRITTEN, 0 SKIP — typing=NEGATIVE gate [no UI surface, verified], draft=
session-cache contract [fork never calls getConversation draft on switch-back;
composer survives via cache, cold-start restore is the recorded gap], recall=
full roundtrip [fork revoke → tox_friend_send_message tombstone → B side gates
recalled-render], receipt ✓✓=keyed fork icon `message_read_receipt_icon:<msgID>`
(+1 automation-only fork key, mobile-covered) · codex 2 rounds: R1 3 P1 (receipt
false-pass on send-state icon → peerRead dump gate added; forward picker
double-fire → tapKeyCenter; draft case asserted nothing → split hard/soft) +
2 P2 — all applied; R2 PASS)

### Batch IV — P1 relaunch trio + calls (`drive_real_ui_pair_p1_relaunch.dart`)

| case | inventory row | notes |
|---|---|---|
| `relaunch_history_autologin` | P1#1 | seed via real composer → relaunch A → autoLogin → history rows render |
| `offline_pending_relaunch` | P1#2 | stop B → A real send → SENDING spinner row → relaunch B → delivered |
| `call_from_profile_tiles` | P1#15 | `friend_profile_voice_call_tile`/`friend_profile_video_call_tile` (fork :437/:455) |
| `group_join_by_id_real_ui` | P1#17 | verify-first AddGroupDialog join path; product-gap record if absent |

Runner: `_realUiStateRelaunchDirty = 'relaunch-dirty'` result state (the existing
unknown-state else-branch already stop+relaunches — verified at
`fixture_c_unified_runner.dart:1075`/`:1614`). Relaunch helper = top-level fn in
the new part (stop/launch scripts + `instance.json` re-read + `Inst._reconnect`).
**STATUS: DONE** (4/4 WRITTEN, 0 SKIP — join-by-id VERIFIED ABSENT → negative
product-gap gate (S33 stays 2proc-l3); relaunch helper relaunches via
`launch_toxee_instance.sh` + fresh `Inst` from re-read instance.json + autoLogin
sessionReady wait; `relaunch-dirty` result state + planner `_restoreForRealUiState`
default-null verified; sweep `sweep_p1_relaunch` · campaign `rui-p1-relaunch` ·
friends→relaunch-dirty · codex R1: 2 P1 (pending-spinner assert raced B-relaunch →
spinner gated BEFORE relaunch + delivered-after; stale-ws dispose leak in relaunch
helper → old vm client disposed before reconnect) + 1 P2 (call cases now
_ensureBothIdle-gated like batch 8) — all applied; R2 PASS)

### Batch V — P2 fork keys + scenarios (`drive_real_ui_pair_p2_keys.dart`)

sticker per-cell key → `sticker_face_cell_send`; new-messages chip key →
`new_messages_chip_tap`; presence-dot semantic state → `presence_dot_relaunch`
(uses relaunch class). Fork commits FIRST (submodule), then toxee SHA bump.
**STATUS: TODO**

### Batch VI — P2 reply two-piece (`drive_real_ui_pair_p2_reply.dart`)

l3 C2C custom-elem inbound seed seam (mirror `l3_inject_group_text` →
`ingestInboundGroupText` seam family) + fork reply-container ValueKey +
`reply_quote_real`. **STATUS: TODO**

### Batch VII — P2 verify-first trio (voice / paste / tray)

Read-code investigations; scenario if surface exists, else evidence-based
product-gap entry HERE + inventory doc cross-ref. **STATUS: TODO**

### Batch VIII — P3 writable subset

`message_burst_perf` (param count + timing, nonBlocking threshold); `ar_rtl_smoke`
(verify ar locale exists; Directionality assert); platform run plan section
(iOS sim / Android / Win11) written here for the run-phase owner. **STATUS: TODO**

## File map (pre-baked anchors for batch agents)

- `lib/ui/testing/ui_drive_tools.dart` (398 LOC): pure handlers + thin MCP entries;
  `resolveKeyCenter` (onstage walk), `_nextPointerId`, `registerUiDriveToolsIfDebug`
  (registered in `main.dart` right after l3 registration, UNGATED kDebugMode-only).
  Hermetic tests: `test/ui/testing/ui_drive_tools_test.dart` (5/5, FakeAsync notes inline).
- `tool/mcp_test/drive_real_ui_pair.dart` (865 LOC): part list :116-131; per-domain
  dispatch switches (batch 4 @~404, 5 @~508, 6 @~589); `settings_sweep` @204,
  `probe_home_root` @727. Add new parts + dispatch entries append-style.
- `tool/mcp_test/drive_real_ui_pair_inst.dart` (READ-ONLY, HOT): `Inst` API —
  ctor `Inst(name, ws, pid)` + `connect()`; `skill()`/`l3()`/`dumpState()`;
  `tapKey/tryTapKey/tapText/tapAt/tapKeyCenter/tapKeyAt/focusType/keyCenter`;
  `scrollAt/scrollAtCoords/dragBy/secondaryTapKey/scrollUntilKey`;
  `waitKey/waitText/waitKeyGone/waitTextGone/waitState`; `foreground/resizeWindow/
  windowSize`; `osaType/osaPaste/osaReturn/osaShiftReturn/osaEscape/osaSearchShortcut/
  osaClear`; `markAccountTest/unmarkAccountTest`; `_reconnect()/_refreshWsUriFromRuntime()`
  (private, same-library callable); `shot(path)`.
- `tool/mcp_test/fixture_c_unified_runner.dart`: `_validRealUiScenarios` @57;
  campaigns map (after the registry); `_requiredRealUiState` @1110 (default at switch
  end); `_resultRealUiState` @1281; symbolic planner @1046 (unknown-state else =
  stop+launch @1075); live executor @1590 (else @1614); `_realUiSkipExitCode` = 75;
  `_internalRealUiResetScenario` @445.
- `lib/ui/testing/ui_keys.dart`: ValueKey catalog (UiKeys.*).
- `lib/ui/testing/l3_debug_tools.dart`: l3 tool registration pattern; test-account
  gate `_activeAccountIsTest` @~377; ungated plumbing precedents
  (`l3_open_group_member_list`, `l3_mark_current_account_test`).
- Fork key precedents: `tencent_cloud_chat_user_profile_body.dart` (call tiles
  :437/:455), `tencent_cloud_chat_message_input_sticker_panel.dart`
  (`desktop_sticker_panel`), `tencent_cloud_chat_group_member_list.dart`
  (member row + kick item keys), `message_list.dart:604` (keyless new-messages chip),
  `conversation_item_online_dot:<convId>` (color-only dot).
- Campaign precedents to copy shape from: `drive_real_ui_pair_settings2.dart`
  (sweep + per-case + normalize-between-cases), `drive_real_ui_pair_login.dart`
  (state-machine order + end-clean guard), `drive_real_ui_pair_group2.dart`
  (2p group prereqs + l3 nav-stability opens).

## Run phase (DEFERRED — owned by a later session)

After sweeps 4–8 finish AND this campaign's write phase closes: rebuild via
`MCP_BINDING=skill TOXEE_BUILD_ONLY=1 ./run_toxee.sh`, run `rui-p1-*`/`rui-p2-*`
campaigns serially, root-cause fixes, then update S*.md headers + INDEX for
validated gates only.

## Batch log (append-only)

- 2026-06-10: anchor created. Parallel session was live-running sweep_contacts
  run phase (commits 125b335, 9c3cedf); user then CANCELLED it and granted full
  file access. Its coherent toxee-side WIP archived as commit 8b62c56
  (focusType always-paste — keystroke mangles even short strings; case-40 remark
  asserts the Prefs-backed `friends[].remark`, root-causing the "expected native
  FAIL" as a wrong-field harness assert). Its tim2tox native WIP
  (`ffi/dart_compat_friendship.cpp`, uncommitted in the submodule) left in place
  — the run-phase owner decides whether the Platform-path finding makes it
  unnecessary (likely) or complementary (binary-replacement path parity).
  Sweep 4–8 run state: sweep_contacts was mid-run when cancelled; sweeps 5–8
  unrun. Instance state unknown — the run phase re-launches fresh.
