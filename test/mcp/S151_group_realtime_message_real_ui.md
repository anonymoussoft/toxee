# S151 — Group: realtime message delivery through the real UI

**Layer**: L3 (MCP playbook)
**Fixture vector**: `paired_for_e2e groups=[gidG joined by both] accounts=2(A,B) autoLogin=on network=online`
**Harness mode**: peerHarness=none (two toxee processes; echo peer is not a substitute)
**Promotion target**: L3-pinned candidate once `2proc-ui` grows a group-message branch; adjacent data-half sibling is S34
**Status**: covered — **live-validated 2026-06-08** on BOTH restored test accounts AND fresh non-test accounts (campaign `accepted-friend-inline-group-message`, 0 fallbacks): handshake PASS → bidirectional real-UI group message delivery PASS (`A->B` and `B->A` both `sent=recv=true`). The earlier "unstable / both directions drop" flakiness was root-caused and fixed: the scenario now creates a PRIVATE NGC group and B AUTO-ACCEPTS the invite over the friend link (not a public DHT join), gates on real peer connection before sending, and retries with a fresh group on the residual same-host cross-process miss. On fresh non-test accounts the create+invite run through the REAL add-group dialog + add-member screen (the l3 setup tools are test-gated; ungated plumbing hooks added). Driver: `drive_real_ui_pair.dart` `group_message`; runner: `--real-ui-scenario=group_message`.

## Precondition
- A and B are both Online and already joined to `<gidG>`.
- Both can open the same group conversation through the real chats UI.

## UI Driver
1. On A, open `<gidG>` and send a unique text through the real composer.
2. On B, poll the real UI for the inbound text.
3. Optionally reverse the direction once.

## Assertions
- The inbound text appears on B without using `l3_send_group_text`.
- The receive path proves the real UI sits on top of the live two-process group transport.
- No runtime errors appear vs baseline on either side.

## Notes
- This is the missing `2proc-ui` sibling of S34.
- The driver/planner gap is closed. The remaining blocker is live NGC group delivery / propagation under real-UI driving: on 2026-06-07 the diagnostic run showed B's candidate conversation present but empty (`messages=[]`) for `A->B`, while A retained only its own self-send for `B->A`.
