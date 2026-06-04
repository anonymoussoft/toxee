# S60 — Responsive layout (window resize → desktop / mobile switch)

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online history=≥1-conv window=1280x800`
**Harness mode**: peerHarness=none
**Promotion target**: L2 candidate — most assertions (sidebar vs bottom-nav presence, profile route shape) can be pumped via `MediaQuery` override hermetically; L3-pinned today because real `windowManager.setSize` is the only honest way to exercise `didChangeMetrics` round-trip plus the `_lastShouldShowMasterDetail` post-frame guard.
**Status**: covered — desktop ↔ responsive layout flip only. Mobile-shape profile route is **deferred** (see A10) until a mobile entry point ships; out of scope for the current scenario.

## Precondition
- Account A signed in, online; ≥1 conversation on disk.
- `windowBounds` pref cleared; `windowMaximized=false`; window launches centered at 1280×800.
- `MCP_BINDING=marionette` and `fmt_evaluate_dart_expression` available.
- macOS arm64. `ResponsiveLayout.isDesktop` is unconditionally true on macOS — all layout flips here are width-driven via `shouldShowBottomNav` (<720) and `shouldShowMasterDetail` (<800).

## Driver
1. Verify sidebar tabs present (`sidebar_chats_tab` etc.) and no `BottomNavigationBar`; sidebar avatar `<nicknameA>\nOnline`. Save `s60_step1_desktop_1280.png`.
2. Tap a conversation row; verify master-detail split (list + chat as siblings under same `Row` ancestor). Save `s60_step2_desktop_master_detail.png`.
3. Drop window minimum and shrink: via `fmt_evaluate_dart_expression`, run `await windowManager.setMinimumSize(Size.zero); await windowManager.setSize(Size(550, 800));`. Wait 500 ms.
4. Re-snapshot; verify mobile-shape (see Assertions). Save `s60_step4_mobile_550.png`.
5. Optional log check: exactly one `setConversationConfig(forceDesktopLayout: false)` log per crossing (observability add — see Notes).
6. Resize back: `await windowManager.setSize(Size(1280, 800));`. Wait 500 ms. Save `s60_step6_desktop_again.png`.
7. Open profile via sidebar avatar at desktop shape; confirm Dialog form factor. (Mobile-shape profile route deferred — no mobile entry point today.)
8. Cleanup: `setMinimumSize(Size(960, 600))`; close.

## Assertions
- A1: At 1280×800 — `sidebar_chats_tab` etc. present; no `BottomNavigationBar` node.
- A2: At 1280×800 — conversation list + chat panel are siblings under a `Row` (master-detail active).
- A3: At 550×800 — no sidebar tabs in tree; `BottomNavigationBar` node with 4 children matching `l10n.chats/contacts/applications/settings`.
- A4: At 550×800 — chat panel is full-width (no sibling conversation list under same `Row`).
- A5: Width-fallback check via platform dispatcher: `width < 720` at 550, `>= 720` at 1280.
- A6: `_lastShouldShowMasterDetail` schedules `setConfigs` exactly once per breakpoint crossing (informational until observability log lands; first build post-launch also fires once).
- A7: Round-trip 1280→550→1280 restores Step 1 sidebar shape (image diff against `s60_step1_desktop_1280.png` within tolerance).
- A8: No `RenderFlex overflowed`, `RenderBox was not laid out`, `hasSize is not true` between resize timestamps.
- A9: `get_runtime_errors({})` no new entries beyond Step 1 baseline.
- A10: Desktop-shape profile open is a `Dialog` widget (Navigator depth +0). Mobile-shape `MaterialPageRoute(fullscreenDialog: true)` (Navigator depth +1) — **deferred** until mobile entry point ships.
- A11: After cleanup, `windowManager.setMinimumSize(960, 600)` is restored.

## Notes
- `desktop_shell_bootstrap.dart:42-43` sets `setMinimumSize(960, 600)`; must be dropped via `fmt_evaluate_dart_expression` before any sub-960 resize. Restore in cleanup.
- macOS `isDesktop` short-circuit (`responsive_layout.dart:44-47`) — never assert `isDesktop==false`; only the `shouldShow*` family flips with width.
- `setConversationConfig` post-frame callback and `_lastShouldShowMasterDetail` are not currently logged; A6 is informational until the observability log lands at `home_page.dart:917-925`.
- `BottomNavigationBarItem` doesn't accept `Key` directly; key the `icon:` via `KeyedSubtree` if anchor keys are added.
- Resize-during-animation race: burst 1280→550 crosses both 800 and 720 in one frame; toxee scaffold swaps to bottom-nav before UIKit chat panel re-renders single-pane. Snapshot may need 200 ms extra slack at Step 4.
- Mobile-shape profile entry is a real product gap surfaced by this scenario.
