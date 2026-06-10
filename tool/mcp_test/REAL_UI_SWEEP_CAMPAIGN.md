# Real-UI sweep campaign — 2026-06-10 (RECOVERY ANCHOR)

> **Purpose of this file:** durable state for the "+94 real-app UI cases" campaign so any
> session (or a fresh Claude session after token exhaustion) can resume exactly where work
> stopped. Update the per-case Status column and the Batch log as work proceeds. Commit
> after every batch.

## Mission (user directive, 2026-06-10)

Cover the majority of common UI scenarios with **real UI tests**: launch the REAL app
(macOS debug bundle) and drive real clicks / scrolls / selections / typing — NOT hermetic
WidgetTester gates. Add **≥80 new cases** (this plan: 94). Constraints:

- **Reuse app launch + accounts aggressively.** No per-case relaunch, no per-case account
  registration, no per-case re-friending. Suites chain many cases on ONE launch (the
  `settings_sweep` precedent) and reuse the `paired_for_e2e` restored fixture state.
- **Single agent (opus), serial** — one batch at a time, no parallel fan-out.
- **Write ALL cases first, then run + fix.** Write phase is hermetic (analyze + planner
  dry-run + hermetic extension-handler tests only; no live app launches).
- Work directly on `master` (standing master-direct directive).
- Deep root-cause fixes for anything the run phase surfaces (no surface patches).
- Codex review mandatory before the campaign is declared done.

## Vehicle

`tool/mcp_test/drive_real_ui_pair.dart` + part files — the real-UI two-process driver
(flutter_skill service extensions + osascript foreground/keystrokes), planned/launched via
`tool/mcp_test/fixture_c_unified_runner.dart` campaigns. Read these FIRST:

- `tool/mcp_test/REAL_UI_TWO_PROCESS.md` — harness facts, gotchas (unfocused-window stall,
  enterText needs focusType-tap, composer needs osascript Return, dialog pop buttons need
  `tapKeyCenter` single-fire, first-run wizard dismissal).
- `tool/mcp_test/drive_real_ui_pair_inst.dart` — `Inst` primitives (tapKey/tryTapKey/
  tapText/focusType/tapAt/osaType/osaReturn/waitKey/waitText/waitState/dumpState/shot/
  foreground, l3 call plumbing).
- `tool/mcp_test/drive_real_ui_pair_shell.dart` — ensureHome (register-once-per-launch),
  recovery, new-entry shell.
- Existing scenario parts (`_friends`, `_message_call`, `_group`, `_settings`,
  `_group_profile`, `_group_menu`) — copy their shape.
- `lib/ui/testing/l3_debug_tools.dart` — l3 tool registration pattern (mcp_toolkit).
- `lib/ui/testing/ui_keys.dart` — ValueKey catalog.

Existing real-UI scenarios (do NOT duplicate): handshake, handshake_detail, decline,
custom_message, message, message_burst, group_message, group_burst, group_member_list,
group_create, settings_sweep (+ copy_id/autologin/notification/export_chooser/password/
logout_relogin/logout_double_fire), group_profile_open, group_rename, group_search,
group_add_member_open, group_add_member_picker, group_conversation_menu,
group_menu_pin_unpin, group_menu_mark_read, group_menu_delete_confirm,
group_menu_mark_read_unread, group_clear_history, group_clear_preserves_pin,
conference_message, probe_home_root, call_voice, call_reject, reset_friendship.

## Batch plan (serial, one opus agent per batch)

Per-batch contract (every agent MUST):
1. Read this file + the harness files above before writing code.
2. Implement its cases as scenario functions in a NEW part file
   `drive_real_ui_pair_<domain>2.dart` (or extend the matching existing part if small),
   register dispatch entries in `drive_real_ui_pair.dart`, add a `sweep_<domain>` scenario
   that chains the batch's cases on one launch with per-case PASS/FAIL summary lines
   (`[sweep] <case>: PASS|FAIL|SKIP(<reason>)` + final counts; exit non-zero if any hard
   case fails), and add campaign entries (`rui-<domain>`) + `_validRealUiScenarios`
   updates in `fixture_c_unified_runner.dart`.
3. Keep `flutter analyze lib tool --no-fatal-warnings --no-fatal-infos` clean and
   `dart run tool/mcp_test/fixture_c_unified_runner.dart --plan-json --class=2proc-ui`
   parsing (planner regression).
4. Real-UI first: drive the production widget/gesture; an l3 bypass is only for SEEDING
   state (e.g. inject inbound history) never for the asserted action itself.
5. Soft-skip protocol: if a case's surface turns out not to exist / not reachable on
   desktop, mark it `SKIP(<reason>)` in the sweep AND in this doc — never fake a pass.
6. Update this file's Status column (TODO → WRITTEN / SKIP+reason) + Batch log, then
   `git commit` (message: `test(real-ui): batch N — <domain> scenarios (written, unrun)`).
7. Do NOT launch the app; do NOT run live scenarios. Hermetic checks only.

### Batch 0 — primitives (PREREQUISITE for scroll/right-click cases)

New file `lib/ui/testing/ui_drive_tools.dart` (debug-only, registered like l3 tools but
UNGATED plumbing — they must work on fresh non-test accounts): service extensions that
dispatch REAL pointer events through `GestureBinding.instance.handlePointerEvent` so the
production gesture/scroll pipeline runs:
- `ui_scroll_at` — PointerScrollEvent (mouse-wheel) at a key's center or raw coords, with
  dx/dy; loop until a target child key is visible (caller-side loop in Inst helper).
- `ui_drag` — pointer down → moves → up between two points (touch-drag scrolling, member
  lists, mobile-style scroll).
- `ui_secondary_tap` — right-button pointer down/up at key center or coords (desktop
  message context menu).
- `ui_hover` — pointer hover event at key center (desktop hover affordances), if needed.
Each takes `{key?|x,y?}` JSON, returns `{ok, error?}`. Hermetic widget tests in
`test/ui/testing/ui_drive_tools_test.dart` proving: a real ListView scrolls + triggers its
scroll callbacks; a GestureDetector.onSecondaryTapDown fires; drag moves a scrollable.
Inst helpers in `drive_real_ui_pair_inst.dart`: `scrollUntilKey`, `secondaryTapKey`,
`dragBy`. Also: investigate + document HERE how the desktop chat message context menu is
actually opened in production (hover-more-button? secondary tap? long-press) — write the
finding into the Batch log; suites 6 depends on it.

**Batch 0 STATUS: DONE** — `lib/ui/testing/ui_drive_tools.dart` (ungated, debug-only)
ships `ui_scroll_at` / `ui_drag` / `ui_secondary_tap` real pointer-event service
extensions; `test/ui/testing/ui_drive_tools_test.dart` 5/5 pass; Inst helpers
(`scrollAt`/`dragBy`/`secondaryTapKey`/`scrollUntilKey`) added; message-menu trigger
investigated (see Batch log).

### Suites (batches 1–8) — 94 cases

Mode: `1i` = single instance (A only, B idle) · `2p` = two-process · `2p-r` = needs
restored/established friendship (plan after handshake or restore `paired_for_e2e`).

#### Batch 1 — Settings sweep 2 (12 cases, 1i, one launch)

| # | Case (scenario id) | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 1 | settings_surface_sections | 1i | — | open settings via sidebar; scroll through; all section headers render | WRITTEN |
| 2 | settings_theme_dark | 1i | S57 | tap theme control → dark applied (widget-tree brightness) + dump persisted | WRITTEN |
| 3 | settings_theme_light_back | 1i | S57 | revert to light; UI re-renders | WRITTEN |
| 4 | settings_locale_zh_roundtrip | 1i | S38 | switch language to 中文 → visible label asserted in Chinese → back to English | WRITTEN |
| 5 | settings_download_limit_edit | 1i | S98 | real field input + save → dump_state threshold | WRITTEN |
| 6 | settings_bootstrap_mode_cycle | 1i | S99/S85 | segmented auto→manual→lan→auto, dump after each | WRITTEN |
| 7 | settings_bootstrap_manual_add_node | 1i | S89 | manual node form: host/port/key input → add → row renders | WRITTEN (form-mount, see log) |
| 8 | settings_bootstrap_manual_remove_node | 1i | S89 | remove the added node → row gone | WRITTEN (collapse-form, see log) |
| 9 | settings_autologin_toggle_hard | 1i | S96 | scrollUntilKey + real tap → dump flips (upgrades documented soft case) | WRITTEN |
| 10 | settings_notifsound_toggle_hard | 1i | S97 | same for notification-sound switch | WRITTEN |
| 11 | settings_password_mismatch_error | 1i | S40 | password dialog: mismatched confirm → inline error, dialog stays | WRITTEN |
| 12 | settings_logout_cancel | 1i | S44 | logout confirm → Cancel → still sessionReady | WRITTEN |

Sweep: `sweep_settings2` · Campaign: `rui-settings2`. **Batch 1 STATUS: DONE** (12/12
cases WRITTEN+unrun; analyze 0-new; planner + campaign-list green; touched-settings
hermetic tests 59/59 still green)

#### Batch 2 — Self profile (8 cases, 1i, same-launch chain)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 13 | profile_open_sidebar_avatar | 1i | S104 | tap sidebar avatar → self-profile overlay mounts | WRITTEN |
| 14 | profile_edit_toggle_roundtrip | 1i | S101 | edit pencil enter/exit edit mode | WRITTEN |
| 15 | profile_edit_nickname_persists | 1i | S8 | edit nickname via real field (+osascript) → save → dump + sidebar reflect | WRITTEN (restores original nick) |
| 16 | profile_edit_status_persists | 1i | S8 | same for status message | WRITTEN (restores original status) |
| 17 | profile_copy_toxid_snackbar | 1i | S102 | copy button → snackbar | WRITTEN |
| 18 | profile_qr_copy | 1i | S103 | QR section copy action → snackbar | WRITTEN (waits for QR FutureBuilder) |
| 19 | profile_avatar_picker_opens | 1i | S79 | avatar tap → default-avatar grid/picker surface mounts (native picker untouched) | SKIP(no in-app avatar picker — native NSOpenPanel only; l3 override test-gated) |
| 20 | profile_avatar_select_default_applies | 1i | S79 | select a bundled default avatar → avatar updates (faceUrl changes) | SKIP(no in-app default-avatar selection surface — same root as 19) |

Sweep: `sweep_profile` · Campaign: `rui-profile`. **Batch 2 STATUS: DONE** (6/8 WRITTEN+unrun, 2 SKIP — no in-app avatar surface; analyze 0-new; planner + campaign-list green; profile hermetic tests 10/10 green)

#### Batch 3 — Login / register (9 cases, 1i; password cases mutate then restore state)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 21 | login_account_card_renders | 1i | S2 | after logout: saved-account card shows nick + tox prefix | WRITTEN |
| 22 | login_register_open_back | 1i | S4 | Register CTA → RegisterPage → back to login | WRITTEN |
| 23 | register_empty_nickname_error | 1i | S4 | submit empty nickname → inline validation error | WRITTEN |
| 24 | register_password_mismatch_error | 1i | S4 | mismatched passwords → inline error | WRITTEN |
| 25 | register_password_strength_flips | 1i | S4 | typing weak→strong flips the strength caption (Weak→Strong) | WRITTEN (added strength caption, see log) |
| 26 | login_restore_entry_opens | 1i | S9/S71 | restore-from-tox card → import/restore surface mounts; cancel back | SKIP(native-picker-only — restore card opens NSOpenPanel directly, no in-app surface) |
| 27 | login_password_wrong_error | 1i | S2b | set pw (settings) → logout → card → wrong pw → error, stays on login | WRITTEN |
| 28 | login_password_correct_unlocks | 1i | S2b | correct pw → HomePage; then REMOVE password (restore no-pw state) | WRITTEN (production UI clears pw, see log) |
| 29 | account_switch_second_account | 1i | S3/S72 | register a 2nd account (ONCE, end of suite) → switch back via login cards; dump shows switched toxId | WRITTEN |

Sweep: `sweep_login` · Campaign: `rui-login`. **Batch 3 STATUS: DONE** (8/9 WRITTEN+unrun,
1 SKIP — case 26 native-picker-only; case 29 registers the ONLY extra account of the
campaign; password cases RESTORE the no-password state via the production change-password
dialog. analyze 0-NEW vs 222 baseline; planner/validate/campaign-list/self-test green;
touched-lib hermetic tests 57/57 green; 4 codex rounds, all findings applied)

#### Batch 4 — Contacts + friend profile (15 cases, 2p; ONE handshake reused; delete/re-add last)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 30 | add_friend_dialog_esc_close | 1i | S5 | new-entry → Add Contact → ESC closes dialog | TODO |
| 31 | add_friend_invalid_id_error | 1i | S5 | garbage ID → inline error, no crash | TODO |
| 32 | add_friend_self_id_guard | 1i | S55 | own tox ID → self-add guard error | TODO |
| 33 | add_friend_duplicate_guard | 2p-r | S56 | friend's ID again → dedup guard error | TODO |
| 34 | contacts_subtabs_cycle | 1i | S106 | New Contacts ↔ Blocked Users sub-tab switching renders each list | TODO |
| 35 | contacts_row_opens_friend_profile | 2p-r | S52 | tap friend row → friend profile sheet mounts | TODO |
| 36 | friendprof_send_message_tile | 2p-r | S115 | Send-Message tile → chat opens for that friend | TODO |
| 37 | friendprof_pin_toggle | 2p-r | S84 | pin switch → pinnedConversations flips + row reorders | TODO |
| 38 | friendprof_block_unblock | 2p-r | S29 | block switch on→off → blockedUsers flips both ways | TODO |
| 39 | friendprof_mute_toggle_regression | 2p-r | S114/S83 | mute switch ×2 → no crash (ABI regression gate) + recvOpt/dump flip | TODO |
| 40 | friendprof_remark_edit_persists | 2p-r | S113/S30 | remark dialog real input → Confirm → UI + dump show remark (KNOWN native bug — expect FAIL → root-cause fix in run phase) | TODO |
| 41 | friendprof_clear_history | 2p-r | S111 | seed a few messages; clear → chat empty + history file cleared | TODO |
| 42 | blocked_list_unblock_row | 2p-r | S107 | block via profile → Blocked Users tab row → unblock button → row gone | TODO |
| 43 | contact_search_filter_clear | 2p-r | S49 | contact search: type filter → matches; clear → full list | TODO |
| 44 | friendprof_delete_friend_confirm | 2p-r | S112/S28 | delete friend → keyed confirm → friend gone both lists (LAST; sweep ends no-friend) | TODO |

Sweep: `sweep_contacts` (handshake once at top) · Campaign: `rui-contacts`. **Batch 4 STATUS: TODO**

#### Batch 5 — Conversation list C2C (10 cases, 2p-r, one launch + one handshake)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 45 | conv_menu_surface_c2c | 2p-r | S117 | right-click/menu on C2C row → menu items render (pin/read/clear/delete) | TODO |
| 46 | conv_pin_unpin_reorders | 2p-r | S116 | pin → row to top + pinned style; unpin → restores | TODO |
| 47 | conv_mark_read_two_proc | 2p-r | S118/S19 | B sends 3 → A unread badge ≥1 → mark-read via row menu → badge gone | TODO |
| 48 | conv_delete_confirm_c2c | 2p-r | S119/S20 | delete via row menu + confirm → row gone, friendship intact | TODO |
| 49 | conv_clear_history_c2c | 2p-r | S111 | clear via row menu → history empty, row survives | TODO |
| 50 | conv_clear_preserves_pin_c2c | 2p-r | — | pin + seed + clear → still pinned (C2C mirror of group gate) | TODO |
| 51 | conv_unread_badge_bump_clear | 2p-r | S90/S19 | B sends → badge N increments; open chat → 0 | TODO |
| 52 | conv_preview_updates_on_inbound | 2p-r | — | B sends nonce → row last-message preview shows it | TODO |
| 53 | conv_presence_dot_flips | 2p-r | S51 | B quits/offline → A presence dot flips; B relaunch → online (uses l3 connection state to detect, real dot asserted) | TODO |
| 54 | conv_search_filter_clear | 2p-r | S48 | conversation search: filter → match; clear → all | TODO |

Sweep: `sweep_conv` · Campaign: `rui-conv`. **Batch 5 STATUS: TODO**

#### Batch 6 — Chat surface C2C (16 cases, 2p-r)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 55 | chat_open_from_row | 2p-r | S11 | tap row → chat opens, header shows friend nick | TODO |
| 56 | chat_multiline_send | 2p-r | S120 | Shift+Enter newline + send → bubble contains both lines; B receives | TODO |
| 57 | chat_long_text_send | 2p-r | — | 600-char message → renders + delivers | TODO |
| 58 | chat_emoji_insert_send | 2p-r | S22 | emoji panel → insert → send → emoji bubble; B receives | TODO |
| 59 | chat_sticker_panel_send | 2p-r | S23 | sticker tab → tap sticker → face message sends; B receives | TODO |
| 60 | chat_msg_menu_surface | 2p-r | S15 | secondary-tap own bubble → context menu items render | TODO |
| 61 | chat_copy_message_clipboard | 2p-r | S16 | menu Copy → OS clipboard contains text (pbpaste) | TODO |
| 62 | chat_reply_quote_roundtrip | 2p-r | S18 | menu Reply → quoted composer → send → quote bubble renders; B sees reply | TODO |
| 63 | chat_forward_to_other_conv | 2p-r | S17 | menu Forward → picker → forward to group → message appears there | TODO |
| 64 | chat_delete_message_gone | 2p-r | — | menu Delete → bubble gone; reopen chat → still gone | TODO |
| 65 | chat_history_scroll_load_more | 2p-r | S14 | seed >1 page (real alternating sends); scroll up → older page loads | TODO |
| 66 | chat_inbound_while_scrolled_up | 2p-r | — | scrolled up + B sends → no forced jump; affordance/indicator asserted | TODO |
| 67 | chat_header_opens_profile | 2p-r | S52 | tap chat header avatar/name → friend profile opens | TODO |
| 68 | chat_offline_pending_then_deliver | 2p-r | S25/S13 | A offline (l3 seed) → send → pending spinner; reconnect → delivered to B | TODO |
| 69 | chat_image_bubble_open_preview | 2p-r | S88 | B sends image (l3_send_file seeding) → A real image bubble renders → tap opens preview | TODO |
| 70 | chat_file_bubble_present_open | 2p-r | S21/S24 | B sends small file (l3 seed) → A file bubble (name+size) → tap dispatches open | TODO |

Sweep: `sweep_chat` · Campaign: `rui-chat`. **Batch 6 STATUS: TODO**

#### Batch 7 — Group + conference (14 cases, mixed)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 71 | group_create_cancel | 1i | S32 | add-group dialog → Cancel → no group created | TODO |
| 72 | group_create_type_selector_surface | 1i | S32 | dialog type selector renders options; pick private → created | TODO |
| 73 | group_profile_members_entry | 1i | S121 | group profile → members entry → member list page | TODO |
| 74 | group_profile_clear_history | 1i | S122 | seed own sends → profile clear-history → chat empty | TODO |
| 75 | group_leave_via_profile_confirm | 1i | S123/S150 | leave/dissolve button → keyed confirm → conv row gone | TODO |
| 76 | group_rename_updates_header | 1i | S153 | rename via profile → open chat header shows new name | TODO |
| 77 | group_add_member_full_join | 2p-r | S124/S81 | add-member picker → invite B → B auto-joins → member list shows 2 | TODO |
| 78 | group_kick_member_ui | 2p-r | S37 | kick B via member-list UI → B's side reflects removal (mesh bootstrap; destructive, LAST group case) | TODO |
| 79 | group_member_list_scroll | 2p-r | S36 | member list drag-scrolls (ui_drag) without error | TODO |
| 80 | group_mute_toggle | 1i | S83 | group profile mute switch → dump flips, no crash | TODO |
| 81 | group_unread_badge_two_proc | 2p-r | S90 | B group-sends → A row badge bumps; open → clears | TODO |
| 82 | conf_create_dialog_surface | 1i | S156 | conference type create → conv row appears | TODO |
| 83 | conf_row_menu_surface | 1i | S161 | conference row menu renders expected items | TODO |
| 84 | conf_member_list_renders | 1i | — | conference profile member list mounts | TODO |

Sweep: `sweep_group2` · Campaign: `rui-group2`. **Batch 7 STATUS: TODO**

#### Batch 8 — Calls + misc (10 cases, 2p-r; media cases consecutive to reuse call state)

| # | Case | Mode | Spec | Drives / asserts | Status |
|---|---|---|---|---|---|
| 85 | call_video_accept_hangup | 2p-r | S66 | video button → B accepts → both inCall → hangup → idle | TODO |
| 86 | call_mute_toggle_incall | 2p-r | S74 | during voice call: mute → state flips → unmute | TODO |
| 87 | call_camera_toggle_incall | 2p-r | S75 | during video call: camera off/on via keyed dock button | TODO |
| 88 | call_missed_record_row | 2p-r | S77 | B calls, B cancels before answer → A missed-call record renders | TODO |
| 89 | call_callee_hangup | 2p-r | S76 | callee (A) ends the call → both sides idle | TODO |
| 90 | call_record_bubble_renders | 2p-r | — | after a completed call: call-record bubble in chat history | TODO |
| 91 | home_tabs_cycle_state_retained | 1i | — | chats→contacts→settings→chats; open chat retained (IndexedStack) | TODO |
| 92 | theme_switch_chat_open | 2p-r | S57 | with chat open: switch dark/light → chat re-renders, no crash, bubbles intact | TODO |
| 93 | window_resize_responsive | 1i | S60 | osascript-resize window narrow → mobile layout swap; restore → desktop (SKIP allowed w/ reason) | TODO |
| 94 | search_chat_history_window_open | 2p-r | S93 | open in-conversation search → type → match highlight surface | TODO |

Sweep: `sweep_calls_misc` · Campaign: `rui-calls-misc`. **Batch 8 STATUS: TODO** (hint:
chain call cases on ONE friendship — voice block then video block; case 93 may use
AppleScript System Events window resize, SKIP with reason if refused)

## Batch log (append-only)

- 2026-06-10: campaign doc created; coverage survey done. Existing real-app coverage =
  ~30 scenarios (list above); everything else is hermetic L1 / l3 data-layer only.
  flutter_skill is a pub package (^0.9.36) with NO scroll/right-click → Batch 0 builds
  our own pointer-event service extensions (real production gesture pipeline).
  App build present at build/macos/Build/Products/Debug/Toxee.app (Jun 9, dylib fresh).

- 2026-06-10 **Batch 0 DONE** (ui_drive pointer primitives, written + hermetically
  verified; NOT yet live-run — needs an app rebuild so the new service extensions are
  in the binary, per the Run-phase protocol):
  - New `lib/ui/testing/ui_drive_tools.dart` (364 LOC; ungated, `kDebugMode`-only;
    registered in `main.dart` via `registerUiDriveToolsIfDebug()` right after the l3
    registration, NOT behind `TOXEE_L3_TEST` so it works on fresh non-test accounts).
    Three tools dispatch genuine `PointerEvent`s through
    `GestureBinding.instance.handlePointerEvent` so the real hit-test / gesture /
    scroll-physics pipeline runs: `ui_scroll_at` (mouse-wheel `PointerScrollEvent`),
    `ui_drag` (touch down→N moves→up, awaited inter-move delay so live frames pump),
    `ui_secondary_tap` (secondary-button mouse down/up). All return
    `{ok, error?, candidates}`. Pure handlers are `@visibleForTesting` and directly
    callable; the `MCPCallEntry`s are a thin wrapper.
  - **Widget resolution / offstage filtering — root-caused a real subtlety.** Keys are
    resolved to the GLOBAL CENTER of their `RenderBox` via `localToGlobal`. The
    documented hazard (key lookups matching widgets in offstage `IndexedStack` subtrees,
    e.g. HomePage's tab IndexedStack) is filtered by walking
    `Element.debugVisitOnstageChildren` from the root rather than `visitChildren` — the
    SAME traversal Flutter's own finders use. NOTE: `IndexedStack` does NOT wrap hidden
    children in a plain `Offstage` widget (Flutter 3.41.9 wraps them in
    `Visibility(maintainSize/State/Interactivity:true)`), so an ancestor-`Offstage`
    scan does NOT catch them — only `debugVisitOnstageChildren` (overridden by
    `_IndexedStackElement` and `_OffstageElement`) prunes them. Candidates are then
    required to be attached, positively-sized RenderBoxes. Offstage-only matches return
    `key_offstage_only:<key>`; absent keys return `key_not_found:<key>` (distinct, via a
    fallback full-tree walk). When multiple onstage matches remain the first is used and
    `candidates` is returned for debuggability. Unique per-call pointer ids (static
    counter from 7000) avoid arena collisions.
  - **FakeAsync deadlock fixed:** `ui_drag`'s inter-move `Future.delayed` is now only
    awaited when `stepDelay > Duration.zero`. A zero-duration `Future.delayed` schedules
    a fake-async timer the widget test can't fire while the handler is suspended → 10-min
    test timeout. Hermetic tests pass `Duration.zero`; production keeps the 16 ms default.
  - Hermetic gates `test/ui/testing/ui_drive_tools_test.dart` (5/5 PASS): scroll moves a
    real ListView offset + fires a ScrollNotification; touch drag scrolls; secondary tap
    fires `GestureDetector.onSecondaryTapDown` once at the widget center; an onstage
    IndexedStack twin is chosen over its offstage sibling (candidates==1, offstage twin
    never fires); an offstage-only key returns `ok:false`/`key_offstage_only` and a typo
    returns `key_not_found`.
  - Inst helpers added to `drive_real_ui_pair_inst.dart` (route to the `ui_*` extensions
    over the existing `l3()` transport): `scrollAt`, `dragBy`, `secondaryTapKey`, and
    `scrollUntilKey` (foreground()s first, fast-paths if target already visible, then
    wheel-scrolls up to maxSteps polling `waitKey`).
  - Quality gates: `flutter analyze lib tool` → 0 NEW issues in touched files (total 222,
    all pre-existing); `check_complexity.dart` does NOT flag ui_drive_tools.dart (364
    LOC); `fixture_c_unified_runner --plan-json --class=2proc-ui` parses + exits 0.
  - **DESKTOP message context-menu finding (for Batch 6):** the desktop chat message menu
    opens via a `Listener` in
    `TencentCloudChatMessageItemWithMenu.desktopBuilder`
    (`third_party/chat-uikit-flutter/.../menu/tencent_cloud_chat_message_item_with_menu.dart:684`):
    `onPointerDown` fires `_openDesktopMessageMenu(event.position)` ONLY when
    `event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton`. It
    is NOT a `GestureDetector.onSecondaryTap` and NOT a hover-more-button — it is a raw
    secondary-button mouse-DOWN on the Listener wrapping
    `widget.methods.getMessageItemWidget(key: _messageKey)`, where `_messageKey == null`
    (the item widget itself is unkeyed on desktop). So `ui_secondary_tap` (which sends a
    `PointerDownEvent(kind: mouse, buttons: kSecondaryMouseButton)`) is EXACTLY the right
    primitive and must hit a point inside that Listener's child. The stable keyed target
    is the ROW container key `ValueKey('message_list_item:<msgID>')`
    (`tencent_cloud_chat_message_row_container.dart:286`) — its center lies inside the
    bubble/Listener region. Batch 6 should `ui_secondary_tap('message_list_item:<msgID>')`
    to open the menu, then tap the keyed items `ValueKey('message_menu_item:<action>')`
    (copy/forward/delete[/recall for a fresh self message]; per the fork, TEXT bubbles
    STRIP reply/multiSelect/translate — see `message_actions_menu_real_ui_test.dart`).
    MOBILE parity trigger: on non-desktop screen modes the same row uses
    `GestureDetector.onLongPress` (`_onLongPressMessageOnMobile`, defaultBuilder:604) — a
    long-press, which `ui_drag`/secondary-tap do not cover; mobile would need a
    long-press primitive or the existing l3 `l3_invoke_message_action` bypass.
  - **Deviations from the spec:** (1) The optional `ui_hover` tool was NOT added — the spec
    marked it "if needed", and the message menu is a secondary-tap (not a hover
    affordance), so no hover is required for the planned scenarios; add it in a later
    batch if a hover-only surface appears. (2) `scrollUntilKey`'s signature uses
    `dyPerStep`/`maxSteps` (negative dy = wheel up to reveal earlier content) matching the
    spec; it foreground()s first like other UI phases.

- 2026-06-10 **Batch 1 DONE** (settings sweep 2 — 12 single-instance cases, WRITTEN +
  hermetically verified; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_settings2.dart` (~560 LOC) declared in
  `drive_real_ui_pair.dart`'s part list; 12 per-case scenario functions + `runSettingsSweep2`
  (chains all 12 on ONE launch, per-case `[sweep] <case>: PASS|FAIL` + final counts, exits
  non-zero if any HARD case fails — all 12 are hard). Each case also dispatchable individually
  in `drive_real_ui_pair.dart` (scenario ids = the campaign table ids). Runner: 13 ids
  (`sweep_settings2` + the 12) added to `_validRealUiScenarios` + both state tables
  (`_requiredRealUiState`/`_resultRealUiState` → `no-friend`, single-instance like
  `group_create`); campaign `rui-settings2 = [sweep_settings2]`. Gates green:
  `flutter analyze lib tool` 222 issues (0 NEW — matches Batch-0 baseline; the new part file
  is clean); `--plan-json --class=2proc-ui` exits 0; `--list-real-ui-campaigns` shows
  `rui-settings2`; `--validate-only` 0; driver `--self-test-shell-recovery` PASS; touched
  settings hermetic tests `flutter test test/ui/settings/` 59/59 PASS (incl. the
  password-mismatch case that mirrors case 11's snackbar + dialog-stays assertions).

  **Key discoveries / production keys used (for later batches):**
  - **Theme (cases 2/3, S57):** the Appearance `SegmentedButton<ThemeMode>` segments carry
    **NO per-segment key** (`global_settings_section.dart` — ButtonSegment takes none), so
    drive by the localized visible label (`tapText('Dark'|'Light'|'System')`). Assert the
    flip via dump `themeMode` (`light|dark|system`, persisted) + label-still-visible (the
    Appearance card didn't crash on rebuild). l3 dump field is `themeMode` (string).
  - **Locale (case 4, S38):** the Language card is an InkWell-collapsing list (NOT a
    SegmentedButton): the collapsed row shows the CURRENT selection's NATIVE label; tapping
    it expands; option labels are language-native literals (`'English'`, `'简体中文'`, …)
    that DON'T change across locale (`appL10n.english => 'English'` even while in zh). So
    revert-to-English works by tapping `English` while the UI is Chinese. dump field is
    `languageCode`; 简体中文 → `zh-Hans`. Chinese label to assert post-switch: `外观`
    (Appearance header). en `Language` header = `语言` in zh (used for re-locating the
    selector to revert).
  - **Download limit (case 5, S98):** `settings_download_limit_field` +
    `settings_download_limit_save_button` (keyed). Save validates `1..10000`. dump field
    `autoDownloadSizeLimit` (int MB). Field is below the fold — scroll onstage first.
  - **Bootstrap mode (case 6, S99/S85):** on DESKTOP the modes are `RadioListTile`s keyed
    `settings_bootstrap_mode_{manual,auto,lan}` (NOT a SegmentedButton — that's the MOBILE
    layout, and it's only manual/auto, NO lan on mobile). dump field `bootstrapNodeMode`.
  - **Manual node form (cases 7/8, S89) — SCOPE DEVIATION, faithful:** the manual node form
    (`manual_node_{host,port,pubkey}_field` + `manual_node_test_button`) only appears in
    manual mode AFTER tapping `manual_node_input_button` to expand. The "Set as Current Node"
    button only renders AFTER a LIVE `addBootstrapNode` TEST SUCCEEDS (needs real DHT
    reachability — non-deterministic in-harness), and there is **NO per-node REMOVE
    affordance anywhere** (manual mode only overwrites the single "current node" card;
    auto-mode "Route selection" → `bootstrap_nodes_page.dart` is a READ-ONLY fetched-node
    list with test/select only). So case 7 asserts the real form MOUNTS + accepts input
    (mode→manual is a real persisted mutation, the S89 surface); case 8 asserts the inverse —
    collapsing the form via the same `manual_node_input_button` toggle makes the field row
    GONE (`waitKeyGone`), then restores mode→auto. Both clearly noted in-code. If a later
    batch needs a true node add/remove, it has to be added to production first.
  - **Switch toggles (cases 9/10, S96/S97) — UPGRADE of the documented soft cases:** the
    OLD `settings_sweep` marked autologin/notification as SOFT because (a) below the fold
    (flutter_skill has no scroll) and (b) flutter_skill's synthetic `tap` doesn't reliably
    toggle a Material `Switch`. Both fixed: (a) Batch-0 `scrollUntilKey` brings the switch
    onstage; (b) `Inst.tapKeyCenter` dispatches a REAL `tapAt` at the switch center (a
    genuine pointer tap, distinct from flutter_skill's synthetic tap) which toggles the
    Switch. Keys: `settings_auto_login_switch` (Account card, upper-mid) /
    `settings_notification_sound_switch` (GlobalSettingsSection, lower). dump bools
    `autoLogin` / `notificationSound`. Both restore the prior value on a pass.
  - **Password mismatch (case 11, S40):** `_showSetPasswordDialog` shows the
    `Passwords do not match` snackbar AND returns WITHOUT `Navigator.pop` on a mismatch — so
    the dialog STAYS open (its `settings_set_password_new_field` key stays in the tree) and
    flutter_skill's double-fire `tap` is SAFE here (no route to double-pop). Confirmed by the
    existing hermetic test `settings_account_password_real_ui_test.dart` ("Mismatched fields:
    do not match SnackBar, dialog stays, nothing saved"). ESC-dismiss after, so no password
    is left set (case 12 relies on a password-free account).
  - **Logout cancel (case 12, S44):** the logout confirm dialog's **Cancel button has NO
    key** (only `settings_logout_confirm_button` is keyed); tap the `Cancel` LABEL. Cancel =
    `popDialogIfCurrent(context, false)` (pops only the dialog, no page-pop), so double-fire
    `tapText` is safe. Assert dialog gone (`waitKeyGone` on the confirm button) + dump
    `sessionReady` STILL true (Cancel must not tear down). The below-fold openers
    (`settings_logout_button`, `settings_set_password_button`) stay on `tapKey` (their direct
    `_tryInvokeCallback` opens the dialog once even off-screen).
  - **PRODUCTION CHANGE (allowed, precedented):** added a stable `ValueKey('settings_scroll_view')`
    (`UiKeys.settingsScrollView`) to the SettingsPage root `ListView` (`settings_page.dart`'s
    build) so `scrollUntilKey`/`scrollAt` have a scroll anchor for the below-fold Global /
    Bootstrap sections. The ListView carries no semantic content, so keying it is
    automation-only and safe; shared Dart, so mobile is covered. Batches 5/6/7 that need to
    scroll other long lists should look for (or add) a similar scrollable key.
  - **Ordering rationale (state-poisoning avoidance):** surface-read first; theme dark→light
    (ends LIGHT, a known state); locale zh→en roundtrip reverts BEFORE the later
    English-text cases so it can't poison them; download-limit + the two switches RESTORE
    their prior values; bootstrap mode cycle ends on `auto`; manual add → remove (collapse)
    leaves the form collapsed + mode auto; password-mismatch ESC-dismisses (no password set);
    `settings_logout_cancel` LAST (only ever taps Cancel → session survives).
  - **No `--boot-restored` / no friendship:** all 12 are single-instance no-friend (like
    `group_create`); the planner launches a FRESH pair (drives only A; B idle) and never
    needs `paired_for_e2e`.
  - **Codex review (2 rounds, mandatory):** round 1 found 5 issues — all applied: (P1)
    locale-expander + theme-segment + manual-node toggles double-fire under flutter_skill's
    `tap` → added a SINGLE-FIRE `_tapTextCenter` (text-matched `tapAt`, twin of
    `Inst.tapKeyCenter`; verified against the flutter_skill 0.9.36
    `interactiveStructured → data.elements[].{key?,text?,bounds{x,y,w,h}}` schema) for the
    label-only controls, and `tapKeyCenter` for the keyed manual-node toggle; (P2) password
    case now requires `dismissed` (dialog gone) in its return; (P2) download-limit +
    bootstrap-remove now require their RESTORE to succeed in the return; (P3) surface_sections
    now asserts the AutoDownload header TEXT (not just the keyed field). Round 2 flagged
    cross-case poison on a mid-sweep FAILURE (a stuck-in-zh locale would false-fail the later
    English-text cases) → added `_normalizeBetweenCases` (idempotent, best-effort, runs after
    EVERY case: reverts locale→en + bootstrap→auto if a prior case left them mutated; never
    throws). Round-2 residual (low severity, ACCEPTED): an individual case that fails its OWN
    restore leaves `autoDownloadSizeLimit` mutated — but the planner launches a FRESH pair per
    campaign run (no same-launch rerun), so it cannot poison a real run; the
    `_normalizeBetweenCases` guard covers the only same-launch poison that actually matters
    (locale + bootstrap mode, which gate later text assertions).

- 2026-06-10 **Batch 2 DONE** (self profile — 6 single-instance cases WRITTEN+unrun, 2
  avatar cases SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_profile.dart` (~530 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 8 per-case functions + `runProfileSweep` (chains all
  8 on ONE launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` + final counts, exits non-zero
  if any HARD case fails — 6 are hard, 2 are SKIPs). Each case individually dispatchable in
  `drive_real_ui_pair.dart` (scenario ids = the campaign table ids). Runner: 9 ids
  (`sweep_profile` + 8) added to `_validRealUiScenarios` + both state tables
  (`no-friend`, single-instance like `sweep_settings2`); campaign `rui-profile =
  [sweep_profile]`. Gates green: `flutter analyze lib tool` 222 (0 NEW — matches the Batch-0
  baseline); `--plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0;
  `--list-real-ui-campaigns` shows `rui-profile`; driver `--self-test-shell-recovery` PASS;
  touched-lib hermetic profile tests `flutter test test/ui/profile_*` 10/10 PASS (the
  `profile_close_button` key addition didn't disturb the close-button test, which still
  finds the close button by its `Icons.close` predicate).

  **Keys used / production keys added (for later batches):**
  - **Self profile is an OVERLAY** (`showSelfProfile` → desktop `showDialog` / mobile
    `MaterialPageRoute`), opened by the persistent sidebar avatar `InkWell`
    (`UiKeys.sidebarUserAvatar == 'sidebar_user_avatar'`) → `_openProfile`. The avatar is
    onstage on EVERY home tab (it's in the left rail `buildSidebar`), so it's reachable from
    chats/contacts/settings alike.
  - **Profile keys already existed** (`ui_keys.dart`, attached to the production widgets in
    `lib/ui/profile/`): `profile_edit_toggle` (IconButton, TOGGLES `_editMode`),
    `profile_nickname_field` + `profile_status_field` (bare keyed `TextField`s, edit-mode
    only), `profile_save_button` (FilledButton, runs `_handleSave` → setState, NO
    Navigator.pop), `profile_tox_id_copy_button` (`_copyToxId` → clipboard +
    `'ID copied to clipboard'` snackbar), `profile_qr_copy_button` (`_copyQrImage` → same
    snackbar — but it only MOUNTS after the QR `FutureBuilder` resolves real canvas→PNG
    generation, so case 18 waits up to 20s for the key), `profile_tox_id_selectable_text`.
  - **PRODUCTION KEY ADDED (allowed, precedented):** `UiKeys.profileCloseButton ==
    'profile_close_button'` on BOTH self-profile overlay close `IconButton`s in
    `lib/ui/settings/sidebar.dart` (the desktop dialog `Positioned` close + the mobile route
    `AppBar` leading close). Lets `_closeSelfProfile` dismiss the overlay deterministically
    (single-fire `tapKeyCenter`, then ESC fallback) between cases, instead of a fragile
    top-right coordinate. Automation-only, shared Dart → mobile covered.
  - **The edit fields DRIVE FINE via `focusType`/`enterText`** (the old REAL_UI_TWO_PROCESS
    "inline edit field/save keys did not land via tap{key}" note is now MOOT for toxee): the
    keys sit directly on the `TextField`s, and `enterText` (no-key) targets the focused
    editable + does a FULL-text `updateEditingValue` REPLACE (so it doesn't matter that
    `osaClear` precedes it — kept as belt-and-suspenders, mirrors settings case 5). Save
    persists to Prefs; assert via `l3_dump_state.nickname` / `.statusMessage` (the latter is
    null→'' coerced, so a restore-to-empty round-trips). Cases 15/16 RESTORE the original
    registered values (poison guard — later batches assert the registered nick).
  - **TOGGLE double-fire discipline:** `profile_edit_toggle` flips `_editMode = !_editMode`,
    so flutter_skill's double-firing `tap` is a net no-op → driven with single-fire
    `tapKeyCenter` (Batch-1 pattern). `_enterProfileEditMode` retries the single-fire toggle
    up to 3× (an even-count correction). The avatar open is ALSO single-fired (tapKeyCenter,
    NO double-fire fallback) so it can't stack two profile dialogs.
  - **AVATAR cases 19/20 SKIP — verified, not assumed (per "don't trust doc conclusions"):**
    read `lib/ui/profile/profile_avatar_picker.dart` + `git show 5867fdc`. The self-profile
    avatar tap (`onAvatarTap → _pickAvatar → pickAndPersistAvatar`) opens the NATIVE
    NSOpenPanel directly via `FilePicker.platform.pickFiles` — there is NO in-app
    default-avatar grid/picker surface (the "default avatars" of 5867fdc are a
    REGISTRATION-TIME fallback INSTALLER in `lib/util/default_avatar_installer.dart`, not a
    chooser UI; the only avatar grid in the tree is upstream UIKit's GROUP-avatar
    `ChooseGroupAvatar`). The l3 override that bypasses the native panel
    (`l3_set_avatar_pick_path` / `l3_pick_avatar`) is TEST-ACCOUNT-gated → refused on the
    fresh non-test real-UI account, and would be a forbidden l3 bypass of the asserted
    action anyway. Both return null (SKIP). NEW runner plumbing: `_realUiSkipExitCode = 75`
    so the individual avatar dispatch returns 75 (the runner logs SKIP + continues, distinct
    from 0=PASS/78=BLOCKED — without this a `null→0` would be tallied a PASS upstream).
  - **No `--boot-restored` / no friendship:** all single-instance no-friend (like
    `sweep_settings2`); planner launches a FRESH pair (drives A; B idle).
  - **Codex review (2 rounds, mandatory):** round 1 found 4 (3 P1 + 1 P2), ALL applied:
    (P1) the avatar SKIP returned exit 0 → reported as PASS upstream → added the
    `_realUiSkipExitCode=75` SKIP code + runner handling; (P1) `_openSelfProfile`
    short-circuited if the overlay was already up → case 13 could false-PASS without tapping
    the avatar → it now CLOSES any pre-existing overlay + asserts `closedBefore` first, and
    `runProfileSweep` normalizes before the first case; (P1) case 18 could false-green on
    case 17's lingering `'ID copied to clipboard'` toast (same text, ~3s lifetime) → added
    `Inst.waitTextGone`, case 17 clears the toast and case 18 REQUIRES it dismissed before
    tapping QR-copy; (P2) the double-fire avatar `tap` could stack two dialogs → switched the
    open to single-fire `tapKeyCenter`. I tried a production re-entry guard in `sidebar.dart`
    but REVERTED it (a module-global flag broke widget-test isolation: `.whenComplete` never
    fires when a test force-dismisses via a direct `onPressed` call — so the guard is a
    harness-layer concern, fixed at the harness layer). Round 2 verified P1.1/P1.2/P1.3
    correct + flagged ONE residual: the `_openSelfProfile` double-fire `tryTapKey` FALLBACK
    was still reachable on a slow/unsized frame → REMOVED the fallback (tapKeyCenter already
    retries bounds 5×/~1s and the avatar is always sized; the outer loop re-foregrounds and
    retries). Round 2 then found no further false-pass/poison/hang.
  - **Mobile parity:** all driven widgets are shared Dart (`lib/ui/profile/`,
    `lib/ui/settings/sidebar.dart`); the `profile_close_button` key is on both the desktop
    dialog and the mobile route close buttons, so the close affordance is covered on mobile
    too. The avatar SKIP applies identically on mobile (the native picker is the only avatar
    surface there as well; there is no in-app default-avatar chooser on any platform).

- 2026-06-10 **Batch 3 DONE** (login / register — 8 single-instance cases WRITTEN+unrun, 1
  SKIP; NOT live-run, per write-phase protocol). New part file
  `tool/mcp_test/drive_real_ui_pair_login.dart` (~1075 LOC) declared in the
  `drive_real_ui_pair.dart` part list; 9 per-case functions + `runLoginSweep` (chains all 9
  on ONE launch, per-case `[sweep] <case>: PASS|FAIL|SKIP` + final counts + `endClean`, exits
  non-zero if any HARD case fails — 8 hard, 1 SKIP). Each case individually dispatchable in
  `drive_real_ui_pair.dart` (scenario ids = the campaign table ids; the single-case dispatch
  runs the minimum prelude each needs — cases that act on the LoginPage log out first). Runner:
  10 ids (`sweep_login` + 9) added to `_validRealUiScenarios` + both state tables
  (`no-friend`, single-instance like `sweep_profile`); campaign `rui-login = [sweep_login]`.
  Gates green: `flutter analyze lib tool` 222 (0 NEW — matches the Batch-0 baseline);
  `--plan-json --class=2proc-ui` exit 0; `--validate-only` exit 0; `--list-real-ui-campaigns`
  shows `rui-login`; campaign expansion + dry-run plan `sweep_login` from a fresh no-friend
  launch (no `--boot-restored`); driver `--self-test-shell-recovery` PASS; touched-lib
  hermetic tests `flutter test test/ui/register/ test/ui/login/ test/ui/testing/l3_debug_tools_environment_test.dart`
  57/57 PASS.

  **State-machine ORDER chosen** (ends CLEAN: logged into the PRIMARY account, NO password,
  autoLogin intact): `ensureHome` (registers the PRIMARY account if the launch is fresh) →
  **logout once** (serves 21+22; lands on LoginPage) → **22** register-open-back → **21**
  account-card-renders → **26** restore-entry (SKIP) → **23/24/25** register validation (NO
  accounts created — all back out) → **quick-login back to primary** (no password) → **27**
  wrong-password (sets a known pw via Settings, logs out, enters WRONG pw → "Invalid
  password", stays) → **28** correct-password (unlocks → HomePage, then REMOVES the password)
  → **29** account-switch (register account #2 nick `RuiSweepB3`, switch back to primary). The
  whole 9-case body runs inside a `try` with an `_ensureCleanPrimaryEnd` END-STATE GUARD in
  the `finally` so a partial run still restores the clean end state.

  **PASSWORD-RESTORE ANSWER (the brief's open question):** the PRODUCTION settings UI CAN
  clear a password — no need to leave the account password-locked. `_showSetPasswordDialog`
  accepts an EMPTY new+confirm (hint text "Leave empty to remove password"); on empty input
  `_setAccountPassword` routes to `AccountService.removeAccountPassword` and shows the
  "Password removed" snackbar. Case 28 unlocks with the correct password, then opens the
  Settings change-password dialog and submits EMPTY fields to restore the no-password state.
  The end state is PROVEN no-password via the new authoritative `currentAccountHasPassword`
  dump field (not the snackbar alone).

  **Case 26 SKIP (verified, not assumed — per "don't trust doc conclusions"):** read
  `lib/ui/login_page.dart` + `login_page_controller.dart`. The "Restore from .tox file" card
  (`UiKeys.loginPageRestoreFromToxFile`) calls `_restoreFromToxFile` →
  `LoginPageController.restoreFromToxFile`, which opens the native `FilePicker.platform.pickFiles`
  DIRECTLY — there is NO in-app pre-picker / options surface to assert mounting. The login
  "settings" entry (`login_page_settings_button`) opens `LoginSettingsPage`, which is the
  bootstrap/global settings page, NOT a restore/import surface. The native panel can't be
  driven headless and there's no test-account l3 override here → SKIP(native-picker-only),
  never a fake pass. (The real restore handler has hermetic controller-seam coverage in
  `test/ui/login/login_restore_import_settings_real_ui_test.dart`.)

  **PRODUCTION CHANGES (3, all intentional + tested + mobile-covered, shared Dart):**
  - `lib/ui/widgets/register_password_strength_bar.dart`: added a localized **Weak/Fair/Good/
    Strong** caption `Text` keyed `register_password_strength_label` under the colored bar (the
    segments' fill is a `BoxDecoration` color, NOT text-matchable by flutter_skill; the caption
    IS — it's the real-UI signal for case 25, and a genuine a11y win: a screen reader now
    announces password strength). 4 new l10n keys in `app_en.arb` + `flutter gen-l10n`
    regenerated (ar/ja/ko/zh fall back to English for these — documented follow-up). The
    existing strength hermetic test extended to assert the caption ramp (0→Weak→Fair→Good→Strong).
  - `lib/ui/login_page.dart`: the saved-account quick-login password dialog `TextField` got
    `key: login_quick_password_field` + `autofocus: true` so the harness can type into it
    deterministically (no key/autofocus before → could not target it). Compatible with the
    existing password-dialog test (which finds the field by type, not key).
  - `lib/ui/testing/l3_debug_tools.dart`: `l3_dump_state` now exposes `currentAccountHasPassword`
    (via a no-throw `_currentAccountHasPassword()` reading `Prefs.hasAccountPassword` on the
    current toxId) — the authoritative no-password ground truth case 28 + the end-clean guard
    gate on (the snackbar alone is ambiguous on a no-password account).

  **Harness keys used:** `register_back_button` (AppBar back), `register_page_*` fields/button,
  `firstRunBackupWizard.laterButton` + `firstRunBackupWizard.confirmDismissButton` (keyed +
  single-pop-guarded — case 29's wizard dismissal single-fires these via `tapKeyCenter`,
  replacing the double-firing text taps `ensureHome` uses), `settings_set_password_*`,
  `settings_logout_*`, `login_page_account_card:<toxId>` (single-fired via `tapKeyCenter`),
  `login_quick_password_field`.

  **Codex review (4 rounds, mandatory — telemetry-off):** round 1 found 5 (3 P1 + 2 P2): clamp
  index type (cosmetic — already compiled via int.clamp, made explicit `.toInt()`); case-27
  could false-pass under a stuck password dialog (added `waitKeyGone(login_quick_password_field)`);
  no end-state restore on a mid-sweep failure → dirty/poisoned 29 (added `_ensureCleanPrimaryEnd`);
  27→28 toxId handoff not enforced (now passes the threaded toxId, empty if 27 failed, so 28
  fails its guard); autoLogin unproven (now printed). Round 2 confirmed P1.1/P1.2/P2 + flagged
  3 (the end-clean guard not no-throw / not reached on early-return; case-29 wizard double-fire;
  endClean false-green). Round 3 fixed those (try/finally + no-throw helper; keyed single-fire
  wizard dismiss; endClean verdict) + flagged 2 (endClean still trusts the ambiguous remove
  snackbar; card taps still double-fire). Round 4 added the `currentAccountHasPassword` ground
  truth + switched all 4 card taps to `tapKeyCenter` + flagged 3 P2 (stale onPrimary; case 28
  not airtight; set-password opener double-fire). Round 4-fix: recompute the whole end-clean
  verdict from one final dump; case 28 also requires `sessionReady && currentAccountToxId==toxId`;
  both password-dialog openers funnel through a single-fire `_openSetPasswordDialog`. Final
  codex pass: **"No remaining P1/P2."**

  **Mobile parity:** all driven widgets + the 3 production changes are shared Dart (login_page,
  register_page, register_password_strength_bar, l3_debug_tools) with no platform split — every
  affordance and the strength caption render identically on iOS/Android/desktop. Case 26's SKIP
  applies on mobile too (the restore card opens the platform file picker there as well; no
  in-app pre-picker exists on any platform).

## Run phase (after ALL batches written) — protocol

1. Rebuild app so new service extensions are in the binary: `./build_all.sh --platform
   macos --mode debug` then **verify the embedded dylib is fresh** (memory: bare
   `flutter build macos` does NOT re-embed; run_toxee.sh / build_all re-embed — nm-verify).
2. Launch the pair ONCE per suite-group: `tool/mcp_test/launch_toxee_instance.sh A/B`
   (or `launch_fixture_c_pair.sh`), restore `paired_for_e2e` where the suite allows
   (`restore_fixture_c_pair.sh`) to skip re-registration/re-friending.
3. Run sweeps serially: suites 1–3 share one single-instance launch where state allows;
   suites 4–8 share the pair launch (reset_friendship between suites that need
   no-friend start).
4. Fix failures at the ROOT CAUSE (native/FFI, fork, app — not the harness, unless the
   harness is provably at fault). Track every fix in the Batch log. Re-run only the
   affected sweep.
5. Update Status column → PASS/FAIL+fix/SKIP+reason.
6. Codex diff review (mandatory): `env -u OTEL_EXPORTER_OTLP_ENDPOINT codex exec -c
   otel.exporter=none -c otel.log_user_prompt=false ...` review of the full campaign diff.
7. Final commit + INDEX regen (`dart run tool/mcp_test/gen_scenario_index.dart --check`).

## Resume instructions (for a fresh session)

1. Read this file top to bottom. `git log --oneline -15` to see which batch commits exist.
2. Find the first batch whose STATUS is not DONE — relaunch the batch agent (opus,
   serial) with the per-batch contract above.
3. If all batches DONE but run phase incomplete: follow Run phase protocol; per-case
   Status shows what already passed.
4. Memories to load: real_ui_two_process_harness, flutter_skill_double_tap_blank,
   real_ui_group_message_private_invite, macos_hang_forensics_first.
