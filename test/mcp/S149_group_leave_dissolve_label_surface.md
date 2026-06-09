# S149 — Group: leave-row label resolves to quit vs dissolve

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidOwnerG, gidMemberG]`
**Harness mode**: peerHarness=none (single-instance label-surface spec; member variant may reuse seeded state)
**Promotion target**: L1/L3 candidate once both owner/member fixtures are available to the runner; adjacent sibling is S123
**Status**: covered at the widget layer — `test/ui/chat_core_real_ui_test.dart` asserts the keyed leave row resolves to `Disband Group` for a non-Work owner and `Leave` for a member.
**Covered-by**: `test/ui/chat_core_real_ui_test.dart`

## Precondition
- One profile render treats A as owner of a non-Work group.
- Another render treats A as a non-owner member of a joined group.

## UI Driver
1. Open the owner-group profile and inspect `UiKeys.groupProfileLeaveButton`.
2. Open the member-group profile and inspect the same row.

## Assertions
- The owner variant labels the row as dissolve.
- The member variant labels the row as quit.
- No runtime errors appear vs baseline.

## Notes
- This isolates the label-resolution logic that S123 discusses in prose.
- The same keyed row and handler back both variants; only role/state changes.
