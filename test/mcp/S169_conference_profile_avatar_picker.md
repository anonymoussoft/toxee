# S169 — Conference: change the conference avatar through the local picker override

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A autoLogin=on network=online groups=[gidC] files=[image]`
**Harness mode**: peerHarness=none (single-instance real UI)
**Promotion target**: L3 candidate once the desktop file-picker surface is automatable in the current harness; adjacent sibling is S139
**Status**: covered at the widget layer — real-UI L1 gate (`test/ui/conference/conference_profile_real_ui_test.dart`).
**Covered-by**: `test/ui/conference/conference_profile_real_ui_test.dart`

## Precondition
- Conference `<gidC>` profile is open.
- A local image fixture is available for the avatar picker.

## UI Driver
1. Tap the conference avatar area in the profile.
2. Pick a local image file.
3. Return to the profile and conversation list.

## Assertions
- The profile avatar updates to the newly selected local image.
- The conversation row reflects the locally overridden avatar on the next render.
- No runtime errors appear vs baseline.

## Notes
- Toxee intentionally makes conference avatars local-only; there is no shared Tox conference avatar concept.
- This is the conference analog of S139.
