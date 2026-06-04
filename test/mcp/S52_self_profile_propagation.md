# S52 — Self profile change propagates to a friend

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=2(A,B in separate macOS Containers) current(A)=A1 current(B)=B1 profileCrypt=plain autoLogin=on network=online friends=1(A↔B paired) dhtCache=warm`
**Harness mode**: peerHarness=none (two real toxees; echo peer is NOT a substitute — playbook §3.7)
**Promotion target**: L3-pinned — B's view of A's changed nickname/avatar rides Tox's `friend_name` callback + a live `TOX_FILE_KIND_AVATAR` (kind=1) file transfer over the DHT; no on-disk seed delivers it.
**Status**: covered by executable Fixture C gates — nickname via `run_fixture_c_self_profile.sh` (B observes friends[].nickName), avatar via `run_fixture_c_avatar.sh` (l3_set_self_profile avatarContent → kind-1 transfer → B's friends[].avatarPath set). Both validated live 2026-06-01.

## Precondition
- A↔B already friends; both plaintext, `autoLogin=on`, `MCP_BINDING=marionette`, distinct `CFBundleIdentifier`.
- Both Online before driving (`<nick>\nOnline` ≤60s/side) — `_sendAvatarToFriendIfNeeded` skips when not connected (`ffi_chat_service.dart:6177`).
- B has a C2C conversation with toxA so its row showName + avatar are mountable.
- A's "before" nickname is a distinct literal (e.g. `Alice Before`) for an unambiguous flip.

## Driver
1. A: open self profile (`sidebar.dart` ProfilePage `isEditable:true`, line 67) → `UiKeys.profileEditToggle` → set `UiKeys.profileNicknameField` to `Alice After` → `UiKeys.profileSaveButton`. Calls `updateSelfProfile` (`sidebar.dart:71`) → `_ffi.setSelfInfo` (`ffi_chat_service.dart:3784`) → `tox_self_set_name` (`V2TIMManagerImpl.cpp:4442`).
2. B: tap `UiKeys.sidebarContacts`; poll snapshot ≤60s — toxA's contact row flips `Alice Before`→`Alice After`; also check Chats-tab C2C row showName.
3. A: change avatar — `onAvatarChanged` (`sidebar.dart:89-96`) → `updateAvatar(path)` → `_sendAvatarToFriendIfNeeded` (kind-1 file).
4. B: poll log ≤120s for inbound avatar `file_done`; poll snapshot for toxA's thumbnail to repaint.

## Assertions
- A1 (nickname send): A log `setSelfInfo`, C++ `SetSelfInfo` (`V2TIMManagerImpl.cpp:4423`) → `tox_self_set_name` (`:4442`) no error.
- A2 (nickname receive, primary): B C++ log `HandleFriendName: Friend <toxA> (<n>) changed name to: Alice After` (`V2TIMManagerImpl.cpp:5699`) → `tim2tox_ffi_save_friend_nickname` (`:5702`) → `NotifyFriendInfoChangedToListener` (`:5745`).
- A3: B enqueues `nickname_changed:<toxA>:Alice After` (`tim2tox_ffi.cpp:1312-1313`); `FfiChatService` parses it (`ffi_chat_service.dart:2556`), `setFriendNickname` (`:2564`), `_nicknameUpdatedCtrl.add` (`:2565`).
- A4: B `_setupNicknameUpdatedListener` (`tim2tox_sdk_platform.dart:2275`) fires `onFriendInfoChanged` (`:2291`) + `notifyConversationChangedForC2C` (`:2294`) — contact row AND C2C row refresh.
- A5 (avatar send): A log `_sendAvatarToFriendIfNeeded: sending avatar to <toxB>` (`ffi_chat_service.dart:6200`) → `_sendAvatarToFriendIfNeeded: sent successfully` (`:6204`).
- A6 (avatar receive, primary): B log `file_done: Detected as AVATAR file (kind=1)` (`:2439`) → `_moveAvatarToAvatarsDir` (`:2442`) → `setFriendAvatarPath` (`:2447`) → `_avatarUpdatedCtrl.add` (`:2453`).
- A7: B `_setupAvatarUpdatedListener` (`tim2tox_sdk_platform.dart:2304`) fires `onFriendInfoChanged` (`:2334`) + `notifyConversationChangedForC2C` (`:2338`) — thumbnail repaints.
- A8 (negative): A log MUST NOT show `skipped – not connected` (`:6177`) / `– hash null` (`:6191`); B MUST NOT show `Avatar move failed` (`:2450`).
- A9: `official.get_runtime_errors({})` empty vs Step-0 baseline on both sessions.

## Notes
- L3-pin: both legs need a live DHT (nickname via `friend_name`; avatar via real kind-1 file transfer). No disk seed delivers B's view; echo peer not a substitute (playbook §3.7).
- Both halves ARE wired (unlike S30's B-block gap): nickname (`HandleFriendName`→`nickname_changed:`→`onFriendInfoChanged`) and avatar (kind-1 file→`onFriendInfoChanged`); should PASS once Fixture C unblocks.
- Status-message is the symmetric third path (`status_changed:` enqueue `tim2tox_ffi.cpp:1325-1326`, parse `ffi_chat_service.dart:2568`); assert it too if the edit changes the status line.
- Avatar send is hash-gated — use a genuinely NEW image or A5/A6 won't fire (`:6213` skip on unchanged hash). Avatar also re-sent on reconnect (`_sendAvatarToAllFriendsOnConnect`, `:6218`).
- Row-key status: `contact_list_tile:<toxId>` and `conversation_list_item:<friendId>` are now available (shared with S30/S51). Remaining gaps for this scenario are in the profile/edit/detail surfaces, not the list rows.
