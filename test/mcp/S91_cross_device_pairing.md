# S91 — Cross-device pairing (host/client, QR + 6-digit SAS, .tox blob)

**Layer**: L1 WidgetTester + L3 (MCP playbook) — desktop paste/loopback is automated; two-device camera scan remains manual
**Fixture vector**: `instances=2 hostAccount=A clientAccount=none network=online(same-LAN) featureFlag=enableQRPairing:ON`
**Harness mode**: `test/ui/pairing/pairing_pages_real_ui_test.dart` mounts the real host/client pages side-by-side and injects only the LAN address + account-blob seams; real two-device camera scan is still Fixture-C-manual.
**Promotion target**: PARTIALLY promoted. The desktop paste-URL path, QR URL production, SAS confirmation buttons on both pages, encrypted blob transfer, and client materializer callback are now hermetic. Hardware camera scanning, compile-time flag entry points, and real human cross-screen comparison remain L3/manual.
**Status**: covered at the unit/logic layer (2026-06-08) and page layer (2026-06-10). `test/pairing/` covers the X25519 ECDH + HKDF session-key derivation, the 6-digit SAS computation, AEAD encrypt/decrypt + tamper-detection, QR/`tox://pair` encode↔decode validation, no-plaintext-`.tox`-blob-on-the-wire regression, full host↔client handshake with injected blob seams, and length-prefixed wire framing. `test/ui/pairing/pairing_pages_real_ui_test.dart` now drives the real `PairingHostPage` + `PairingClientPage` UI in one process: host renders the QR URL, client pastes it, both render and tap "The codes match", and the client receives the decrypted profile bytes. Feature **C6** (配对（跨设备）：主机/客户端、QR + SAS 6 位、`.tox` blob 传输; `lib/util/pairing/`, `lib/ui/pairing/`).
**Covered-by**: `test/pairing/pairing_wire_test.dart`, `test/pairing/pairing_handshake_test.dart`, `test/ui/pairing/pairing_pages_real_ui_test.dart`

## Precondition
- **Feature flag is OFF in production**: `FeatureFlags.enableQRPairing == false` (`feature_flags.dart:38`). The host entry (`settings_page_build.dart:511`, `settings_page.dart:1057`) and client entry (`login_page.dart:1207` / `790-797`) are both gated on it — neither renders unless the flag is flipped true in a local build. Any run of this scenario REQUIRES rebuilding with the flag enabled.
- Two app instances on the same LAN (the host binds `0.0.0.0`, advertises a LAN IPv4 via `PairingLan.findLanAddress`, `pairing_host_page.dart:77/112/119`; client connects to that LAN address). No common LAN interface → host shows `pairingNoLanInterface` and aborts (`pairing_host_page.dart:78-84`).
- Instance A: signed-in account A (the `.tox` blob source — `PairingHostPage(toxId: A)`). Instance B: on LoginPage (the importer — `PairingClientPage`).
- `MCP_BINDING=marionette` on both instances (separate VM URIs).

## Driver
1. **Host (A)**: Settings → tap the pair-as-host action (`_startPairingAsHost`, `settings_page.dart:1057-1062`) → `PairingHostPage` mounts, renders a QR (`_QrPlate`/`QrImageView`, `pairing_host_page.dart:290/342`) encoding the `tox://pair?key=...` URL. State key `qr-ready` (`pairing_host_page.dart:235-241`).
2. **Client (B)**: LoginPage → tap the pair-with-device action (`login_page.dart:797` → `PairingClientPage`). On mobile a camera scanner mounts (`MobileScanner`, `pairing_client_page.dart:261`); on desktop a paste-URL TextField is shown (`pairing_client_page.dart:294-321`, `_supportsCameraScan == false`).
3. **Transport handshake**: B receives the URL (scan or paste → `_onUrlReceived`, `pairing_client_page.dart:78`) → `PairingClient.connect(url)`. Both sides derive the SAS over X25519 ECDH (`pairing_crypto.dart:155-169`) and emit `*AwaitingSas` → each page renders the formatted 6-digit code (`_SasBlock` host `pairing_host_page.dart:292-300`; `_buildSasView` client `pairing_client_page.dart:350-395`).
4. **SAS confirmation (human)**: a person compares the two 6-digit codes; if equal, tap "the codes match" on BOTH (`pairingCodesMatch` → `confirmSas`, host `pairing_host_page.dart:297`, client `pairing_client_page.dart:385`).
5. **Blob transfer**: host streams A's exported `.tox` bytes (`loadProfileBlob` via `AccountExportService.exportAccountData`, `pairing_host_page.dart:88-111`); client imports them (`materializeProfile` → `AccountExportService.importAccountData`, `pairing_client_page.dart:83-115`) and emits `ClientCompleted(toxId)`.

## Assertions
- A1: host snapshot reaches state `qr-ready` with a rendered QR; client reaches state `sas` after connect.
- A2: the 6-digit SAS shown on host == the SAS shown on client (both derived identically, `pairing_crypto.dart` `_bytesToSasCode`, `sasDigits = 6`, modulo 10^6, zero-padded — `pairing_crypto.dart:52/264-280`). Format is `XXX XXX` (`_format`, `pairing_host_page.dart:385-388`).
- A3: after both confirm, host reaches `pairingHostCompleted` (`pairing_host_page.dart:244-250`) and client reaches `pairingClientCompleted` with a non-empty toxId (`pairing_client_page.dart:147/225-231`).
- A4: on the client, the imported account appears in the saved-accounts list with the host's toxId (post-`importAccountData`).
- A5 (security): the host's temp `.tox` export is zero-filled + deleted in `finally` (`pairing_host_page.dart:107-109/171-194`); the client's temp incoming blob is deleted in `finally` (`pairing_client_page.dart:107-114`).

## Notes
- **Why no executable gate**: `tool/mcp_test/drive_fixture_c_pair.dart` is named "pair" but drives the FRIEND-ADD handshake (`l3_add_friend_request`, `drive_fixture_c_pair.dart:69/239`), NOT this QR/SAS device-pairing UI. There is no `l3_pair_*` tool and no `drive_fixture_c_qrpair` runner. Do NOT claim a Fixture-C gate covers C6.
- **Three hard automation blockers**: (1) the feature flag is `false`; (2) the QR step needs a camera (mobile) or a human paste (desktop) — `mobile_scanner` cannot be MCP-driven; (3) the SAS step is a deliberate human equality check across two screens. The unit-test seams (`exportServiceForTest`, `materializeProfileForTest`) bypass disk but still require both `PairingHost`/`PairingClient` halves wired in one test harness, which is a transport unit test, not this cross-device scenario.
- A desktop-to-desktop variant can skip the camera by pasting the `tox://pair?key=...` URL into the client's paste field (`pairing_client_page.dart:313-321`), but still needs two instances + the manual SAS confirm + the flag.
- Echo seed context: the paired peer Tox id used elsewhere in fixtures is `3116CBE0…7244`; it is NOT relevant here — C6 transfers a full `.tox` identity blob, not a friend handshake to a known peer.
