# S54 — Friend request custom message round-trips to the recipient

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate macOS Containers) current(A)=A1 current(B)=B1 autoLogin=on network=online friends=none(pre-pair)`
**Harness mode**: peerHarness=none (needs a second toxee, NOT an echo peer — echo auto-accepts and exposes no inbound application-item UI)
**Promotion target**: L3-pinned — the custom message rides a live `tox_friend_add` over the DHT and surfaces in B's in-memory `pending_applications_` (C++-only, no on-disk file to inject). Sibling of S26.
**Status**: covered by executable Fixture C gate — `tool/mcp_test/run_fixture_c_custom_message.sh` (fresh base: recipient `autoAcceptFriends=false` confirmed before send, sender sends `tox_friend_add` carrying a distinctive custom message, recipient observes the EXACT wording as a pending application via `l3_dump_state.friendApplications[].wording`; asserts the request was NOT auto-accepted). Driver uses the stable B→A direction (sender=B, recipient=A); the round-trip contract is direction-agnostic. Validated live 2026-06-01.

## Precondition
- Two toxees, separate macOS Containers, distinct `CFBundleIdentifier` (e.g. `com.toxee.b.app`) — same as S26.
- Both plaintext, `autoLogin=on`, `MCP_BINDING=marionette`.
- B's `acct_auto_accept_friends_<toxB_prefix16>` = `false` (else `_acceptFriendApplications`, `home_page_bootstrap.dart:826`, fires before the request item is asserted and the row never renders).
- Both Online before driving (`<nick>\nOnline` ≤60s/side). A↔B not yet friends.

## Driver
1. Both: `official.get_runtime_errors({})` baseline.
2. A: `sidebar_contacts_tab` → `new_entry_menu_button` (wait ~500 ms for popup) → `new_entry_add_contact_item`.
3. A: snapshot → assert `AddFriendDialog` mounted (`UiKeys.addFriendIdInput`, `UiKeys.addFriendMessageInput`, `UiKeys.addFriendSubmitButton`).
4. A: `enter_text` `UiKeys.addFriendIdInput` = toxB 76-hex address.
5. A: clear `UiKeys.addFriendMessageInput`, `enter_text` a DISTINCTIVE message `S54-CUSTOM-<nonce>` (override the auto-seeded `defaultFriendRequestMessage`, `add_friend_dialog.dart:105-107`). NOTE: an empty message is rejected client-side (`add_friend_dialog.dart:128`), so a non-empty custom message is required.
6. A: re-snapshot ≤500 ms → assert `addFriendSubmitButton.enabled == true` (`_canSubmit`, both controllers non-empty).
7. A: tap `UiKeys.addFriendSubmitButton`; poll for the success SnackBar.
8. B: `sidebar_contacts_tab`; poll snapshot ≤30s for `UiKeys.contactApplicationItem("<toxA>")` (`contact_application_item:<toxA>`) and the companion `UiKeys.contactApplicationAddWording("<toxA>")` text node carrying the custom message.

## Assertions
- A7 (sender SnackBar, secondary): success text = `_localeText(context, 'requestSent', fallback: 'Friend request sent')` (`add_friend_dialog.dart:138-139`), which resolves to `TencentCloudChatLocalizations.of(context).requestSent ?? fallback` (`add_friend_dialog.dart:520,527-528`). With the UIKit delegate registered (it is), the live string is the vendor value — en `Request Sent` (`...localizations_en.dart:449`); the APP fallback `Friend request sent` only shows if `t == null`. Assert the locale-appropriate vendor string, fall back to `Friend request sent`. Dialog dismisses ≤2s.
- A8 (round-trip, PRIMARY): B's snapshot shows the New Contacts row for toxA AND a `Text` widget whose content == the EXACT `S54-CUSTOM-<nonce>` from Step 5 (`getAddWording`, `tencent_cloud_chat_contact_application_list.dart:275-288` renders `addWording` verbatim; empty → `Container()` at `:281`, so a blank message is a false pass — use the nonce).
- A8 (log, B): `HandleFriendRequest from <toxA> with message: S54-CUSTOM-<nonce>` (`V2TIMManagerImpl.cpp:5563`) AND `[HandleFriendRequest] Created application: userID=<toxA>, addWording=S54-CUSTOM-<nonce>` (truncated 40 chars, `:5583-5584`) AND `[NotifyFriendApplicationListAdded] Adding application[..]: userID=<toxA>, addWording=S54-CUSTOM-<nonce>` (`V2TIMFriendshipManagerImpl.cpp:89-90`).
- Path (reference): dialog message → `addFriend(rawId, requestMessage:)` (`add_friend_dialog.dart:208`) → `FfiChatService.addFriend(requestMessage:)` (`ffi_chat_service.dart:1319-1323`; default `Hello from Flutter UIKit client` only if empty) → `tox_friend_add` carrying `addWording` (`V2TIMFriendshipManagerImpl.cpp:664-665`) → B `HandleFriendRequest` (`V2TIMManagerImpl.cpp:5536`), `application.addWording = requestMessage` (`:5574`) → `FakeFriendApplication.wording` → `V2TimFriendApplication.addWording` (`home_page_bootstrap.dart:798`) → UIKit `Text`.
- Negative (A): keep the message ≤ `_kMaxFriendRequestLength` (921, `add_friend_dialog.dart:20`) or the validator (`friendRequestMessageTooLong`, `:264-265`) rejects it client-side and it never sends. Post-submit log MUST NOT contain `cannot add yourself` / `already in friend list` / `addFriend failed`.
- Both: `official.get_runtime_errors({})` back to baseline.

## Notes
- L3-pin: round-trip is fully implemented (dialog → `addFriend` `requestMessage` → C++ `addWording` → B's application-item `Text`); the pin is live DHT delivery + B's `pending_applications_` being C++-in-memory only (no on-disk inject, same as S26).
- Use a distinctive nonce, NOT the seeded default: empty/absent `addWording` renders `Container()` (`...application_list.dart:280-281`), so asserting the default risks confusion with the auto-seeded text.
- Two-sandbox mandatory (mirror S26): echo peer NOT a substitute — auto-accepts, surfaces no inbound application UI. Stays blocked per playbook §3.7.
- Key status: `contact_application_item:<userID>` and `contact_application_addwording:<userID>` are now available to target the application row and its wording text directly instead of label-matching.
