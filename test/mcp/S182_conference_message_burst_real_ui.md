# S182 — Conference: alternating burst send through the real UI

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e groups=[gidC joined by both] accounts=2(A,B) autoLogin=on network=online history=empty`
**Harness mode**: peerHarness=none (two toxee processes; live conference transport required)
**Promotion target**: L3-pinned candidate once `2proc-ui` grows a reusable conference-burst campaign; adjacent siblings are S152 and S64
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_composer_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_composer_real_ui_test.dart`

## Precondition
- A and B share joined conference `<gidC>`.
- Both sides can focus the real conference composer.

## UI Driver
1. Alternate A->conference and B->conference sends for a short burst.
2. Poll both real UIs until the tail messages land.

## Assertions
- The full burst lands on both sides in the expected order/window.
- The real UI remains stable under repeated focus/type/send cycles.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the conference analog of S152.
- It is especially useful because legacy conference delivery has historically been a distinct backend branch.
