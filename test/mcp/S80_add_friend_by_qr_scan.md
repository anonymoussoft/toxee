# S80 — Add a friend by scanning their QR code

**Layer**: L3 (MCP playbook)
**Fixture vector**: `accounts=1 current=A1 autoLogin=on network=online friends=0 platform=ios|android`
**Harness mode**: peerHarness=echo_live
**Promotion target**: L3-pinned — needs real OS camera permission + a live camera feed showing a friend's QR + a real DHT `addFriend`; none of that is L1/L2-reachable. The QR-payload→validator→`addFriend` tail (post-scan) is L1-promotable (drive `_idController.text = <hex>` then `_submit`).
**Status**: covered

## Precondition
- Account A signed in (plaintext), sidebar `<nicknameA>\nOnline`.
- Running on iOS or Android — `_supportsCameraScan` gates the QR button to `Platform.isAndroid || Platform.isIOS` (`add_friend_dialog.dart:283-284`); on macOS/desktop the scanner IconButton is not rendered (Paste only).
- OS camera permission pre-granted (one-time manual approval or `tccutil`; iOS `NSCameraUsageDescription` present `ios/Runner/Info.plist:78-79`; macOS string omits QR/pairing wording, `macos/Runner/Info.plist:33-34`).
- A friend's Tox-ID QR is physically presentable to the camera. The canonical payload is the **raw 76-hex Tox ID string** (no URL/JSON prefix) — same encoding toxee renders on the profile QR card (`add_friend_dialog.dart:295-298`; display side `lib/ui/profile/profile_qr_section.dart` + `QrImageView` via `qr_flutter`, raw-hex payload per `profile_qr_controller.dart`).
- Echo peer running (`bash tool/mcp_test/ensure_echo_peer.sh`); its `peer_id` rendered as a QR to scan. `MCP_BINDING=marionette`.

## Driver
1. Poll snapshot ≤60s for sidebar `<nicknameA>\nOnline`.
2. `marionette.tap({ key: "sidebar_contacts_tab" })` (`UiKeys.sidebarContacts`) — NewEntryButton lives in the contacts AppBar only.
3. `marionette.tap({ key: "new_entry_menu_button" })` (`UiKeys.newEntryMenuButton`); wait ~500ms for menu animation.
4. `marionette.tap({ key: "new_entry_add_contact_item" })` (`UiKeys.newEntryAddContactItem`) → `AddFriendDialog` mounts.
5. Tap the QR scan IconButton (`Icons.qr_code_scanner_rounded`, tooltip `Scan QR`/`scanQr`) in the ID field suffix (`add_friend_dialog.dart:411-418`; no UiKey yet — tap by tooltip/ref). `_scanQr` pushes `_ScanToxIdPage` fullscreen.
6. Present the friend's QR to the camera. `_ScanToxIdPage._onDetect` decodes the first non-empty barcode and pops the raw value (`add_friend_dialog.dart:596-604`).
7. Re-snapshot dialog within ≤500ms → `add_friend_id_input` now holds the 76-hex; assert `add_friend_submit_button.enabled == true`.
8. `marionette.tap({ key: "add_friend_submit_button" })` (`UiKeys.addFriendSubmitButton`).

## Assertions
- A1: scanner page mounts — `MobileScanner` present; `MobileScannerController(formats:[qrCode])` (`add_friend_dialog.dart:584-587,616-619`).
- A2 (primary): after scan, `add_friend_id_input` text == scanned 76-hex (trimmed), matching `^[0-9a-fA-F]{76}$` (`_scanQr` sets `_idController.text = scanned.trim()`).
- A3 (double-fire guard): `_handled` ensures only the first decoded frame pops (`add_friend_dialog.dart:579,597,602`); ID field is set once, not appended.
- A4: submit `enabled` flips false→true after fill (shared `_canSubmit` gate with S5).
- A5 (online): SnackBar `Request Sent` (the live string is `TencentCloudChatLocalizations.requestSent` = `Request Sent`; see Notes); echo peer log within 60s: `OnFriendRequest from=<LOCAL_TOXID>`.
- A6: post-submit negative grep: `cannot add yourself`, `already in friend list`, `addFriend failed` MUST NOT appear.
- A7: `official.get_runtime_errors({})` empty vs Step 1 baseline.

## Notes
- L3-pin = OS camera permission + live camera feed + live DHT; the scan→validator→addFriend tail without a camera is L1-promotable.
- Status scope (mobile only): the scanner is gated by `_supportsCameraScan` (`add_friend_dialog.dart:283`, `!kIsWeb && (Platform.isAndroid || Platform.isIOS)`), so desktop has NO scanner IconButton rendered (Paste only). `covered` applies on iOS/Android; the QR DISPLAY side (profile card, pairing host) renders on all platforms but is a separate flow.
- A5 string: the app calls `_localeText(context, 'requestSent', fallback: 'Friend request sent')` (`add_friend_dialog.dart:139`), which returns `t?.requestSent ?? fallback` (`:528`). The UIKit delegate `TencentCloudChatLocalizations.requestSent` resolves to `Request Sent` (`tencent_cloud_chat_intl/.../l10n_en.arb:224`), so the delegate is non-null and the `Friend request sent` fallback is NOT used at runtime. Assert `Request Sent`.
- Payload contract is bare 76-hex (no URL/JSON); the existing `_validateToxId` rejects anything else — a QR encoding a `tox:`/URL payload would fail validation, not auto-strip.
- Wanted UiKeys: `add_friend_qr_scan_button`, `scan_tox_id_page`, `scan_tox_id_result` (none exist; tap by tooltip/ref today). `_ScanToxIdPage` title is a hardcoded English `'Scan QR'` (no ARB key, `add_friend_dialog.dart:608-611`). Distinct from `lib/ui/pairing/pairing_client_page.dart` (also `mobile_scanner`) which scans a device-pairing QR (login), NOT a friend Tox-ID.
