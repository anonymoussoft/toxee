// Real-UI two-process driver.
//
// Unlike the l3_* "debug bypass" drivers (drive_fixture_c_*.dart), this drives
// the REAL UIKit widgets across two live instances via the `flutter_skill`
// service extensions (tap / enterText / waitForElement / screenshot), i.e. it
// exercises the actual buttons/fields a user touches ("直接驱动 UI 控件").
//
// Hard-won harness facts (see /tmp diagnostics + REAL_UI_GATES notes):
//   * The instances are raw-launched (`launch_toxee_instance.sh`, direct exec).
//     An UNFOCUSED macOS window does NOT pump frames / service platform
//     channels, so any async UI step (route push, SharedPreferences read) STALLS
//     while backgrounded. FIX: osascript-foreground the target pid before each
//     UI phase. Data/DHT keeps running on native threads regardless, so the
//     other instance can be backgrounded between phases.
//   * `flutter_skill.enterText{key}` only matches an *editable* widget carrying
//     the key; our keys sit on TextFormField wrappers, so use focusType =
//     tap{key} (general widget search) then enterText{no key} into the focus.
//   * `flutter_skill.screenshot` returns {image:<base64 png>} but only when the
//     window is foreground (else empty).
//
// Usage:
//   dart run tool/mcp_test/drive_real_ui_pair.dart <scenario> \
//       <wsA> <pidA> <nickA> <wsB> <pidB> <nickB>
// scenarios:
//   handshake         S26 + S61 — B sends an add-friend request, A ACCEPTS via
//                     the INLINE row button (contact_application_accept_button);
//                     asserts friendship + nickname propagation both directions.
//   handshake_detail  S108 — same, but A accepts via the pushed application-
//                     DETAIL screen (contact_application_detail_accept_button),
//                     the distinct UI entry point S26 does NOT exercise.
//   decline           S27 — A DECLINES the inbound request; asserts the
//                     application cleared and no friendship formed.
//   message           S62 + S64 — bidirectional message delivery through the
//                     REAL composer + a real Return (RUITEST_STAMP=<n> for a
//                     stable nonce).
//
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';

class DriveError implements Exception {
  DriveError(this.message);
  final String message;
  @override
  String toString() => 'DriveError: $message';
}

class Inst {
  Inst(this.name, this.ws, this.pid);
  final String name;
  final String ws;
  final int pid;
  late final VmService vm;
  late final String iso;

  Future<void> connect() async {
    vm = await vmServiceConnectUri(ws);
    final v = await vm.getVM();
    final isos = v.isolates ?? const <IsolateRef>[];
    iso = isos
        .firstWhere(
          (i) => (i.name ?? '').toLowerCase().contains('main'),
          orElse: () => isos.first,
        )
        .id!;
    // Wait for the skill + l3 extensions to be live.
    await _waitExt('$_skillNs.tap');
    await _waitExt('$_mcpNs.l3_dump_state');
  }

  Future<void> _waitExt(String name, {int timeoutSecs = 60}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final i = await vm.getIsolate(iso);
      if ((i.extensionRPCs ?? const <String>[]).contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    throw DriveError('[$name] extension never registered on ${this.name}');
  }

  Future<void> dispose() => vm.dispose();

  Future<Map<String, dynamic>> _raw(
    String method,
    Map<String, Object?> params,
  ) async {
    final strArgs = <String, String>{
      for (final e in params.entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    final resp = await vm.callServiceExtension(
      method,
      isolateId: iso,
      args: strArgs,
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<Map<String, dynamic>> skill(
    String m, [
    Map<String, Object?> p = const {},
  ]) => _raw('$_skillNs.$m', p);

  Future<Map<String, dynamic>> l3(
    String m, [
    Map<String, Object?> p = const {},
  ]) => _raw('$_mcpNs.$m', p);

  /// macOS-foreground this instance's window. Required before any UI phase.
  Future<void> foreground() async {
    final r = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    if (r.exitCode != 0) {
      print('[$name] WARN foreground failed: ${r.stderr}');
    }
    await Future<void>.delayed(const Duration(milliseconds: 700));
  }

  Future<Map<String, dynamic>> dumpState({String? userId}) =>
      l3('l3_dump_state', userId == null ? const {} : {'userId': userId});

  Future<void> tapKey(String key, {int retries = 6}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    throw DriveError('[$name] tapKey "$key" failed after $retries tries');
  }

  Future<void> tapText(String text, {int retries = 6}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'text': text});
      if (r['success'] == true) return;
      await Future<void>.delayed(const Duration(milliseconds: 800));
    }
    throw DriveError('[$name] tapText "$text" failed after $retries tries');
  }

  /// Best-effort tap-by-key; returns whether it landed (no throw).
  Future<bool> tryTapKey(String key, {int retries = 3}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) return true;
      await Future<void>.delayed(const Duration(milliseconds: 600));
    }
    return false;
  }

  /// Focus a (possibly TextFormField-wrapped) field by key, then type into the
  /// focused editable.
  Future<void> focusType(String key, String text) async {
    await tapKey(key);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final r = await skill('enterText', {'text': text});
    if (r['success'] != true) {
      throw DriveError('[$name] focusType "$key" enterText failed: $r');
    }
  }

  Future<void> tapAt(num x, num y) async {
    await skill('tapAt', {'x': x, 'y': y});
  }

  // --- Real OS input (foreground window). The desktop chat composer is an
  // ExtendedTextField whose ExtendedEditableText cannot be driven by synthetic
  // enterText, and Enter-to-send rides the legacy FocusNode.onKey RawKeyEvent
  // path — both need genuine OS events. ---
  Future<void> _osa(String script) =>
      Process.run('osascript', ['-e', script]);
  Future<void> osaType(String text) =>
      _osa('tell application "System Events" to keystroke "$text"');
  Future<void> osaReturn() =>
      _osa('tell application "System Events" to key code 36');
  Future<void> osaClear() async {
    await _osa('tell application "System Events" to keystroke "a" using command down');
    await _osa('tell application "System Events" to key code 51');
  }

  Future<bool> waitKey(String key, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {'key': key, 'timeout': '$timeoutSecs'});
    return r['found'] == true;
  }

  Future<bool> waitText(String text, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {'text': text, 'timeout': '$timeoutSecs'});
    return r['found'] == true;
  }

  /// Poll a top-level dump_state scalar until [test] passes.
  Future<Map<String, dynamic>> waitState(
    bool Function(Map<String, dynamic>) test, {
    int timeoutSecs = 60,
    String label = 'state',
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    Map<String, dynamic> last = const {};
    while (DateTime.now().isBefore(deadline)) {
      last = await dumpState();
      if (test(last)) return last;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw DriveError('[$name] waitState "$label" timed out; last=$last');
  }

  Future<void> shot(String path) async {
    final r = await skill('screenshot');
    final img = r['image'] as String?;
    if (img == null || img.isEmpty) {
      print('[$name] shot empty (window backgrounded?)');
      return;
    }
    await File(path).writeAsBytes(base64Decode(img));
    print('[$name] shot -> $path');
  }
}

/// Recover the real-UI automation from non-Home startup pages that block the
/// register/login flow — primarily the `sc_load_account_fail.png` "Startup
/// Failed: Profile not found for account" page. A stale saved account whose
/// on-disk profile was wiped (common in the multi-instance harness, where the
/// per-instance profile dir is cleared but the account_list pref persists)
/// triggers a FAILED auto-restore on boot, so the app parks on that error page
/// with Retry / "Go to Login" buttons instead of the register/login UI that
/// [ensureHome] expects. Without this, ensureHome fails opaquely with
/// `tapText "Register new account" failed after 6 tries`.
///
/// Strategy: if the Startup-Failed page is showing, tap "Go to Login" to route
/// to the saved-accounts/register page; re-evaluate until we reach a
/// register-capable page (or sessionReady). Returns best-effort after
/// [maxRounds] so the caller still surfaces a clear downstream error.
Future<void> recoverStartupExceptions(Inst inst, {int maxRounds = 4}) async {
  for (var round = 0; round < maxRounds; round++) {
    await inst.foreground();
    final st = await inst.dumpState();
    if (st['sessionReady'] == true) return;
    // sc_load_account_fail: "Startup Failed" / "Exception: Profile not found".
    if (await inst.waitText('Startup Failed', timeoutSecs: 2)) {
      print('[${inst.name}] sc_load_account_fail detected '
          '(stale account, profile missing) -> tapping "Go to Login"');
      await inst.tapText('Go to Login');
      await Future<void>.delayed(const Duration(milliseconds: 1500));
      continue; // re-evaluate the page we landed on
    }
    // Register-capable page reached (blank register OR saved-accounts list,
    // both expose the "Register new account" affordance).
    if (await inst.waitText('Register new account', timeoutSecs: 2)) return;
    // Unknown transient page (route still settling); let frames pump and retry.
    await Future<void>.delayed(const Duration(milliseconds: 1000));
  }
  print('[${inst.name}] WARN: startup recovery exhausted after $maxRounds '
      'rounds; proceeding best-effort');
}

Future<void> ensureHome(Inst inst, String nickname) async {
  await inst.foreground();
  final st = await inst.dumpState();
  if (st['sessionReady'] == true) {
    // A booted session has navigated past login/register; just make sure the
    // window is foregrounded so any in-flight frame settles.
    print('[${inst.name}] already logged in (${st['nickname']})');
    await inst.waitKey('new_entry_menu_button', timeoutSecs: 10);
    return;
  }
  // Handle the sc_load_account_fail.png "Startup Failed" page (and similar
  // non-Home startup exceptions) before assuming the register page is showing.
  await recoverStartupExceptions(inst);
  print('[${inst.name}] registering "$nickname" via real UI...');
  await inst.tapText('Register new account');
  await Future<void>.delayed(const Duration(seconds: 2)); // route transition
  await inst.focusType('register_page_nickname_field', nickname);
  await Future<void>.delayed(const Duration(milliseconds: 400));
  await inst.tapKey('register_page_register_button');
  // Boot can take several seconds; keep foreground so frames pump.
  await inst.foreground();
  await inst.waitState(
    (s) => s['sessionReady'] == true,
    timeoutSecs: 60,
    label: 'sessionReady',
  );
  // First-run backup wizard blocks navigation; dismiss it.
  await inst.foreground();
  if (await inst.waitText('Save your account file', timeoutSecs: 20)) {
    await inst.tapText("I'll do it later");
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    await inst.tapText('I understand, continue');
  }
  if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 25)) {
    throw DriveError('[${inst.name}] did not reach HomePage after register');
  }
  print('[${inst.name}] on HomePage ($nickname)');
}

/// B drives the add-friend dialog targeting A's tox id (real UI).
Future<void> driveAddFriend(Inst b, String toxA) async {
  await b.foreground();
  await b.tapKey('new_entry_menu_button');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await b.tapKey('new_entry_add_contact_item');
  await Future<void>.delayed(const Duration(milliseconds: 800));
  await b.focusType('add_friend_id_input', toxA);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await b.tapKey('add_friend_submit_button');
  print('[${b.name}] add-friend submitted toward ${toxA.substring(0, 16)}...');
}

String _pubkey(String id) {
  final u = id.trim().toUpperCase();
  return u.length >= 64 ? u.substring(0, 64) : u;
}

/// A navigates Contacts -> New Contacts and accepts (or declines) B via the
/// real keyed buttons.
Future<void> driveRespondToApplication(
  Inst a,
  String toxB, {
  required bool accept,
}) async {
  await a.foreground();
  await a.tapKey('sidebar_contacts_tab');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  // NOTE: UiKeys.contactNewContactsTab ('contact_new_contacts_tab') does NOT
  // match the navigable row in this UIKit build (key sits on a non-tappable
  // wrapper). tapText('New Contacts') matches the PAGE TITLE (top-left), not the
  // master-list ROW, so the right-hand "New Application" detail never loads and
  // Accept/Decline never render. Tap the master-list row by coordinates
  // (1280x768 window: the first row under the Contacts sub-tab) to open the
  // application list. Finding to fix in the fork: give the row a tappable key.
  if (!await a.tryTapKey('contact_new_contacts_tab')) {
    await a.tapText('New Contacts');
    await a.tapAt(240, 173);
  }
  // Wait for B's application to arrive in the model.
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any((e) =>
          e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB));
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app = apps.firstWhere(
    (e) => e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
  ) as Map;
  final userId = app['userId'].toString();
  print('[${a.name}] application present (userId=${userId.substring(0, 16)}...)');
  await a.foreground();
  // APP-SIDE FINDING: the New Contacts detail panel does NOT live-refresh when
  // an application arrives while it is already open — the master-row badge
  // increments but the detail keeps showing "0 New Applications". The early
  // navigation above (done before B's request landed) rendered an EMPTY detail,
  // and re-tapping the already-selected New Contacts row is a no-op. So navigate
  // AWAY (Blocked Users row) then BACK to New Contacts to force a fresh detail
  // load that renders the now-present application + its Accept/Decline buttons.
  await a.tapAt(240, 270); // Blocked Users master row
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await a.tapAt(240, 173); // New Contacts master row (fresh load)
  await Future<void>.delayed(const Duration(milliseconds: 900));
  final keyBase = accept
      ? 'contact_application_accept_button'
      : 'contact_application_decline_button';
  // Prefer the keyed control; fall back to the visible Accept/Decline label.
  if (!await a.tryTapKey('$keyBase:$userId')) {
    await a.tapText(accept ? 'Accept' : 'Decline');
  }
  print('[${a.name}] tapped ${accept ? "ACCEPT" : "DECLINE"} on real UI');
}

/// S108: A opens B's application DETAIL screen (not the inline row button) and
/// accepts there. The row's GestureDetector.onTap calls `gotoApplicationInfoPage`
/// which Navigator.push-es `TencentCloudChatContactApplicationInfo`; its accept
/// control is `contact_application_detail_accept_button:<userId>`. The detail
/// accept does NOT pop the route (just safeSetState), so the flutter_skill
/// double-fire is harmless here.
Future<void> driveRespondViaDetail(Inst a, String toxB) async {
  await a.foreground();
  await a.tapKey('sidebar_contacts_tab');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!await a.tryTapKey('contact_new_contacts_tab')) {
    await a.tapText('New Contacts');
    await a.tapAt(240, 173);
  }
  // Wait for B's application to arrive in the model.
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any((e) =>
          e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB));
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app = apps.firstWhere(
    (e) => e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
  ) as Map;
  final userId = app['userId'].toString();
  print('[${a.name}] application present (userId=${userId.substring(0, 16)}...)');
  await a.foreground();
  // Same away-and-back refresh the inline path needs: the detail panel does not
  // live-refresh when the application lands while it is already open. Use
  // generous settles — a too-short settle leaves the right pane on its stale
  // "0 New Applications" render and the row never appears.
  await a.tapAt(240, 270); // Blocked Users master row
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  await a.tapAt(240, 173); // New Contacts master row (fresh load)
  await Future<void>.delayed(const Duration(milliseconds: 2000));
  // OPEN the detail screen by tapping the application ROW (the left text area —
  // the inline Accept/Decline buttons sit at the far right ~x:1148). The row's
  // `contact_application_item:<userId>` KeyedSubtree wraps a GestureDetector that
  // key/text-tap can't land, so tap by coordinates: first row at y~208 in the
  // 1280x768 window. The row.onTap → gotoApplicationInfoPage pushes the detail.
  await a.tapAt(700, 208);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  final onDetail = await a.waitKey(
    'contact_application_detail_accept_button:$userId',
    timeoutSecs: 10,
  );
  if (!onDetail) {
    throw DriveError(
      '[${a.name}] detail screen accept button not found for $userId',
    );
  }
  print('[${a.name}] detail screen open; tapping DETAIL accept');
  await a.tapKey('contact_application_detail_accept_button:$userId');
  print('[${a.name}] tapped DETAIL ACCEPT on real UI');
}

Future<bool> areFriends(Inst x, String otherTox) async {
  final s = await x.dumpState();
  final friends = (s['friends'] as List?) ?? const [];
  return friends.any(
      (f) => f is Map && _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox));
}

Future<String> friendNick(Inst x, String otherTox) async {
  final s = await x.dumpState();
  for (final f in (s['friends'] as List? ?? const [])) {
    if (f is Map && _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox)) {
      return f['nickName']?.toString() ?? '';
    }
  }
  return '';
}

// Logical-pixel center of the desktop composer text field (1280x768 window).
const _composerX = 830;
const _composerY = 702;

/// Open the C2C chat with [friendPubkey] (64-char) by tapping the contact tile.
Future<void> openChat(Inst inst, String friendPubkey) async {
  await inst.foreground();
  await inst.tapKey('sidebar_contacts_tab');
  await Future<void>.delayed(const Duration(milliseconds: 600));
  await inst.tapKey('contact_list_item:$friendPubkey');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

/// Type [text] into the REAL composer and send it with a REAL Return, retrying
/// the focus+Return until the conversation's last message actually becomes
/// [text] (the legacy RawKeyEvent send races a freshly-typed field, so a single
/// Return is unreliable — verify-and-retry).
Future<bool> sendComposerMessage(Inst inst, String text) async {
  await inst.foreground();
  await inst.tapAt(_composerX, _composerY);
  await Future<void>.delayed(const Duration(milliseconds: 500));
  await inst.osaClear();
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.osaType(text);
  await Future<void>.delayed(const Duration(milliseconds: 800));
  for (var attempt = 0; attempt < 6; attempt++) {
    await inst.foreground();
    await inst.tapAt(_composerX, _composerY); // ensure keyboard focus
    await Future<void>.delayed(const Duration(milliseconds: 450));
    await inst.osaReturn();
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (await _lastMessage(inst) == text) return true;
  }
  return false;
}

Future<String> _lastMessage(Inst inst) async {
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is Map && c['lastMessageText'] != null) {
      return c['lastMessageText'].toString();
    }
  }
  return '';
}

Future<bool> _waitLastMessage(Inst inst, String text, {int timeoutSecs = 60}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _lastMessage(inst) == text) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// S62/S64: bidirectional message delivery driven through the REAL composer
/// across two processes. Assumes A and B are already friends.
Future<int> runMessage(Inst a, Inst b, String nickA, String nickB, int stamp) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final bobPk = _pubkey(toxB);
  final alicePk = _pubkey(toxA);
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] message scenario requires an existing friendship; run handshake first');
    return 1;
  }
  final m1 = 'RUITEST-AtoB-$stamp';
  final m2 = 'RUITEST-BtoA-$stamp';

  await openChat(a, bobPk);
  final aOk = await sendComposerMessage(a, m1);
  final bGot = await _waitLastMessage(b, m1, timeoutSecs: 60);
  print('[pair] A->B sent=$aOk received=$bGot ("$m1")');

  await openChat(b, alicePk);
  final bOk = await sendComposerMessage(b, m2);
  final aGot = await _waitLastMessage(a, m2, timeoutSecs: 60);
  print('[pair] B->A sent=$bOk received=$aGot ("$m2")');

  await a.shot('/tmp/ui_message_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_message_B.png');

  if (aOk && bGot && bOk && aGot) {
    print('[pair] PASS: bidirectional real-UI message delivery');
    return 0;
  }
  print('[pair] FAIL: A->B(sent=$aOk,recv=$bGot) B->A(sent=$bOk,recv=$aGot)');
  return 1;
}

Future<int> main(List<String> args) async {
  if (args.length < 7) {
    print('usage: drive_real_ui_pair.dart <scenario> '
        '<wsA> <pidA> <nickA> <wsB> <pidB> <nickB>');
    return 64;
  }
  final scenario = args[0];
  final a = Inst('A', args[1], int.parse(args[2]));
  final nickA = args[3];
  final b = Inst('B', args[4], int.parse(args[5]));
  final nickB = args[6];
  await a.connect();
  await b.connect();
  try {
    if (scenario == 'message') {
      // Stamp passed via env (scripts can't use DateTime determinism concerns here).
      final stamp = int.tryParse(
              Platform.environment['RUITEST_STAMP'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return await runMessage(a, b, nickA, nickB, stamp);
    }
    await ensureHome(a, nickA);
    await ensureHome(b, nickB);

    final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
    final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
    if (toxA.isEmpty || toxB.isEmpty) {
      throw DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print('[pair] toxA=${toxA.substring(0, 16)}.. toxB=${toxB.substring(0, 16)}..');

    // Wait for both connected to the DHT before the handshake.
    await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
    await b.waitState((s) => s['isConnected'] == true, label: 'B connected');

    final accept = scenario != 'decline';
    await driveAddFriend(b, toxA);
    if (scenario == 'handshake_detail') {
      // S108: accept via the pushed application-DETAIL screen, not the inline row.
      await driveRespondViaDetail(a, toxB);
    } else {
      await driveRespondToApplication(a, toxB, accept: accept);
    }

    // Verify outcome.
    if (accept) {
      await a.waitState(
        (_) => true,
        timeoutSecs: 1,
      );
      final aHasB = await _retryBool(() => areFriends(a, toxB),
          label: 'A has B as friend');
      final bHasA = await _retryBool(() => areFriends(b, toxA),
          label: 'B has A as friend');
      // Name-propagation regression gate (the register-time setSelfInfo bug):
      // each peer must see the OTHER's registered nickname, not the raw tox-id.
      final aSeesNick = await _retryBool(
          () async => (await friendNick(a, toxB)) == nickB,
          label: 'A sees B nickname "$nickB"');
      final bSeesNick = await _retryBool(
          () async => (await friendNick(b, toxA)) == nickA,
          label: 'B sees A nickname "$nickA"');
      print('[pair] names: A sees B="${await friendNick(a, toxB)}" '
          'B sees A="${await friendNick(b, toxA)}"');
      await a.shot('/tmp/ui_${scenario}_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_${scenario}_B.png');
      if (aHasB && bHasA && aSeesNick && bSeesNick) {
        print('[pair] PASS: friendship + name propagation both directions');
        return 0;
      }
      print('[pair] FAIL: aHasB=$aHasB bHasA=$bHasA '
          'aSeesNick=$aSeesNick bSeesNick=$bSeesNick');
      return 1;
    } else {
      // Decline: application should clear on A and no friendship forms.
      await Future<void>.delayed(const Duration(seconds: 3));
      final stillFriend = await areFriends(a, toxB);
      final apps = ((await a.dumpState())['friendApplications'] as List?) ?? const [];
      final appGone = !apps.any((e) =>
          e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB));
      await a.shot('/tmp/ui_${scenario}_A.png');
      if (!stillFriend && appGone) {
        print('[pair] PASS: decline removed application, no friendship');
        return 0;
      }
      print('[pair] FAIL: stillFriend=$stillFriend appGone=$appGone');
      return 1;
    }
  } on DriveError catch (e) {
    print('[pair] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

Future<bool> _retryBool(
  Future<bool> Function() body, {
  required String label,
  int attempts = 30,
  int intervalMs = 1000,
}) async {
  for (var i = 0; i < attempts; i++) {
    if (await body()) return true;
    await Future<void>.delayed(Duration(milliseconds: intervalMs));
  }
  print('[retry] "$label" never became true');
  return false;
}
