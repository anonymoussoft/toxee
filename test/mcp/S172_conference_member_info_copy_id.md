# S172 — Conference: copy a member ID from member info

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate sandboxes) current(A)=A1 autoLogin=on network=online groups=[gidC joined by both]`
**Harness mode**: peerHarness=none (two toxee processes; remote member required)
**Promotion target**: L3 candidate once member-info actions are runner-covered; adjacent sibling is S171
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_members_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_members_real_ui_test.dart`

## Precondition
- A has opened B's member info inside conference `<gidC>`.

## UI Driver
1. Trigger the copy-ID action from the member info surface.
2. Read the clipboard.

## Assertions
- The copied value matches B's member identifier as shown in the member info view.
- The action is non-destructive and keeps the member info surface mounted.
- No runtime errors appear vs baseline.

## Notes
- This is the conference analog of S142.
- The same upstream member info view is reused under group/conference contexts.
