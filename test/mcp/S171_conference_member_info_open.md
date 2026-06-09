# S171 — Conference: open member info from the member list

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 autoLogin=on network=online groups=[gidC joined by both]`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3 candidate once a real-ui two-process member-list runner exists; adjacent sibling is S141
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_members_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- Conference `<gidC>` has at least one remote member B besides A.
- A can open the conference profile and member list.

## UI Driver
1. Open the conference profile.
2. Enter the member list.
3. Tap B's member row.

## Assertions
- The member info surface opens for B.
- The opened member info shows B's display name and identifier.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S141.
- A remote member is required; self-only conferences cannot exercise this path.
