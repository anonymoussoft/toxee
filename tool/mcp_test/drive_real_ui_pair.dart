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
//       [--boot-restored] <wsA> <pidA> <nickA> <wsB> <pidB> <nickB>
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
//   custom_message    S54 — B sends a friend request carrying a distinctive
//                     custom message; A verifies the wording round-trips, then
//                     declines the request so the pair returns to no-friend.
//   call_voice        S65 + S67 + S76 — with an existing friendship, B starts
//                     a voice call from the real chat header, A accepts via the
//                     real incoming-call UI, then B hangs up.
//   call_reject       S68 — with an existing friendship, B starts a voice call
//                     and A rejects it via the real incoming-call UI.
//   message_burst     S64 — a short alternating burst through the real
//                     composer on an already-friended pair.
//   probe_home_root   restored-live probe: drive into a routed chat, then
//                     verify l3_force_home_root(tab: contacts|chats) restores
//                     the expected shell without sidebar-click recovery.
//   reset_friendship  Internal runner utility: if A and/or B are currently
//                     friends, delete the friendship through the real profile
//                     UI until both sides are back to a no-friend state.
//
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';
const _sidebarTabX = 50;
const _sidebarChatsY = 220;
const _sidebarContactsY = 288;

class _LocalVmServiceHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(
    Uri url,
    Map<String, String>? environment,
  ) {
    final host = url.host.toLowerCase();
    if (host == '127.0.0.1' || host == 'localhost' || host == '::1') {
      return 'DIRECT';
    }
    return super.findProxyFromEnvironment(url, environment);
  }
}

class DriveError implements Exception {
  DriveError(this.message);
  final String message;
  @override
  String toString() => 'DriveError: $message';
}

class PermissionBlockedError extends DriveError {
  PermissionBlockedError(super.message);
}

bool _isNonTestAccountError(Object e) => '$e'.contains('non_test_account');

class Inst {
  Inst(this.name, this.ws, this.pid);
  final String name;
  final String ws;
  final int pid;
  late VmService vm;
  late String iso;

  Future<void> connect() async {
    await _connectVmWithRetry();
    // Wait for the skill + l3 extensions to be live.
    await _waitExt('$_skillNs.tap');
    await _waitExt('$_mcpNs.l3_dump_state');
  }

  Future<void> _connectVmWithRetry({int attempts = 15}) async {
    Object? lastError;
    for (var attempt = 1; attempt <= attempts; attempt++) {
      try {
        vm = await vmServiceConnectUri(ws);
        final v = await vm.getVM();
        final isos = v.isolates ?? const <IsolateRef>[];
        iso = isos
            .firstWhere(
              (i) => (i.name ?? '').toLowerCase().contains('main'),
              orElse: () => isos.first,
            )
            .id!;
        return;
      } catch (e) {
        lastError = e;
        try {
          await vm.dispose();
        } catch (_) {}
        if (attempt < attempts) {
          await Future<void>.delayed(Duration(milliseconds: 800 * attempt));
        }
      }
    }
    throw DriveError(
      '[$name] failed to connect VM service at $ws after $attempts attempts: '
      '$lastError',
    );
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

  Future<void> _reconnect() async {
    print('[$name] VM service connection dropped — reconnecting $ws');
    try {
      await vm.dispose();
    } catch (_) {}
    await _connectVmWithRetry();
  }

  bool _isDisposedError(Object e) {
    final s = '$e';
    return s.contains('disposed') ||
        s.contains('WebSocket') ||
        s.contains('Connection closed');
  }

  Future<Map<String, dynamic>> _raw(
    String method,
    Map<String, Object?> params,
  ) async {
    final strArgs = <String, String>{
      for (final e in params.entries)
        e.key: e.value is String ? e.value as String : jsonEncode(e.value),
    };
    Future<Map<String, dynamic>> once() async {
      final resp = await vm.callServiceExtension(
        method,
        isolateId: iso,
        args: strArgs,
      );
      return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    }

    try {
      return await once();
    } catch (e) {
      if (!_isDisposedError(e)) rethrow;
      await _reconnect();
      return once();
    }
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

  Future<void> bootExistingAccount(String toxId, String nickname) async {
    final r = await l3('l3_boot_existing_account', {
      'toxId': toxId,
      'nickname': nickname,
    });
    if (r['ok'] != true) {
      throw DriveError('[$name] l3_boot_existing_account failed: $r');
    }
  }

  Future<void> clearActiveConversation() async {
    final r = await l3('l3_clear_active_conversation');
    if (r['ok'] != true) {
      throw DriveError('[$name] l3_clear_active_conversation failed: $r');
    }
  }

  Future<void> forceHomeRoot({String tab = 'chats'}) async {
    final r = await l3('l3_force_home_root', {'tab': tab});
    if (r['ok'] != true) {
      throw DriveError('[$name] l3_force_home_root failed: $r');
    }
  }

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
  Future<void> _osa(String script) async {
    final r = await Process.run('osascript', ['-e', script]);
    if (r.exitCode != 0) {
      final stderrText = '${r.stderr}'.trim();
      final suffix = stderrText.contains('not allowed to send keystrokes')
          ? ' (macOS Accessibility permission missing for osascript/System Events)'
          : '';
      if (stderrText.contains('not allowed to send keystrokes')) {
        throw PermissionBlockedError(
          '[$name] osascript failed (exit ${r.exitCode}): $stderrText$suffix',
        );
      }
      throw DriveError(
        '[$name] osascript failed (exit ${r.exitCode}): $stderrText$suffix',
      );
    }
  }

  Future<void> osaType(String text) =>
      _osa('tell application "System Events" to keystroke "$text"');
  Future<void> osaReturn() =>
      _osa('tell application "System Events" to key code 36');
  Future<void> osaEscape() =>
      _osa('tell application "System Events" to key code 53');
  Future<void> osaClear() async {
    await _osa(
      'tell application "System Events" to keystroke "a" using command down',
    );
    await _osa('tell application "System Events" to key code 51');
  }

  Future<bool> waitKey(String key, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {
      'key': key,
      'timeout': '$timeoutSecs',
    });
    return r['found'] == true;
  }

  Future<bool> waitText(String text, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {
      'text': text,
      'timeout': '$timeoutSecs',
    });
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
      print(
        '[${inst.name}] sc_load_account_fail detected '
        '(stale account, profile missing) -> tapping "Go to Login"',
      );
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
  print(
    '[${inst.name}] WARN: startup recovery exhausted after $maxRounds '
    'rounds; proceeding best-effort',
  );
}

Future<void> ensureHome(
  Inst inst,
  String nickname, {
  bool requireHomeMenu = true,
}) async {
  await inst.foreground();
  final st = await inst.dumpState();
  if (st['sessionReady'] == true) {
    // A booted session has navigated past login/register; just make sure the
    // window is foregrounded so any in-flight frame settles.
    print('[${inst.name}] already logged in (${st['nickname']})');
    if (!requireHomeMenu ||
        await _chatsHomeReady(inst, timeoutSecs: 2) ||
        await inst.waitKey('new_entry_menu_button', timeoutSecs: 2)) {
      return;
    }
    if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 6)) {
      // A previous scenario may have left us on Contacts/Profile/Chat detail.
      // Normalize back to the Chats home before continuing.
      if (await inst.waitText('Back', timeoutSecs: 2)) {
        await inst.tapText('Back');
        await Future<void>.delayed(const Duration(milliseconds: 800));
      } else if (!await _selectChatsTab(inst)) {
        try {
          await inst.osaEscape();
        } on DriveError {
          // Best effort only: avoid tapping the top-left self-avatar hotspot.
        }
        await Future<void>.delayed(const Duration(milliseconds: 800));
        await _selectChatsTab(inst);
      }
      if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 8)) {
        if (await _recoverBlankHomeRoot(inst) &&
            await inst.waitKey('new_entry_menu_button', timeoutSecs: 8)) {
          return;
        }
        throw DriveError('[${inst.name}] did not recover to HomePage');
      }
    }
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
    if (!await _tryTapText(inst, 'I understand, continue')) {
      await inst.tapAt(894, 520);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }
  if (!requireHomeMenu) {
    return;
  }
  if (!await inst.waitKey('new_entry_menu_button', timeoutSecs: 25)) {
    throw DriveError('[${inst.name}] did not reach HomePage after register');
  }
  print('[${inst.name}] on HomePage ($nickname)');
}

Future<void> returnToChatsHome(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'returnToChatsHome',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await inst.waitText('Back', timeoutSecs: 1)) {
      await inst.tapText('Back');
    } else if (!await _selectChatsTab(inst)) {
      if (await _recoverBlankHomeRoot(inst)) {
        continue;
      }
      if (await _forceHomeRootAndWait(
        inst,
        tab: 'chats',
        label: 'returnToChatsHome fallback',
        ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
      )) {
        return;
      }
      try {
        await inst.osaEscape();
      } on DriveError {
        // Best effort only: some shells ignore ESC, but it is safer than
        // tapping the top-left avatar area which opens the self-profile modal.
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_chats_${inst.name}.png';
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-chats snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasChatsSidebar=$hasChatsSidebar hasContactsSidebar=$hasContactsSidebar '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to Chats home');
}

Future<void> ensureContactsShell(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureContactsShell',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await _selectContactsTab(inst)) {
      continue;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureContactsShell fallback',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _tryTapText(inst, 'Back')) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _recoverBlankHomeRoot(inst)) {
      continue;
    }
    try {
      await inst.osaEscape();
    } on DriveError {
      // Best effort only.
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_contacts_${inst.name}.png';
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-contacts snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasChatsSidebar=$hasChatsSidebar hasContactsSidebar=$hasContactsSidebar '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to Contacts shell');
}

Future<void> ensureNewEntryShell(Inst inst, {int rounds = 4}) async {
  for (var round = 0; round < rounds; round++) {
    await inst.foreground();
    if (await _newEntryShellReady(inst, timeoutSecs: 2)) {
      return;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureNewEntryShell',
      ready: () => _newEntryShellReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _recoverActiveConversation(inst)) {
      continue;
    }
    if (await _recoverFriendProfileToContacts(inst)) {
      continue;
    }
    if (await _dismissProfileQrOverlay(inst)) {
      continue;
    }
    if (await _selectContactsTab(inst)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'ensureNewEntryShell fallback',
      ready: () => _newEntryShellReady(inst, timeoutSecs: 2),
    )) {
      return;
    }
    if (await _tryTapText(inst, 'Back')) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _selectChatsTab(inst)) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await _recoverBlankHomeRoot(inst)) {
      continue;
    }
    try {
      await inst.osaEscape();
    } on DriveError {
      // Best effort only.
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  final st = await inst.dumpState();
  final shotPath = '/tmp/recover_new_entry_${inst.name}.png';
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-new-entry snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'shot=$shotPath',
  );
  throw DriveError('[${inst.name}] failed to recover to new-entry shell');
}

Future<void> _ensureRestoredHome(Inst inst, _RestoredAccount restored) async {
  await inst.foreground();
  final st = await inst.dumpState();
  if (st['sessionReady'] == true) {
    if (await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'restored session preflight',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
    )) {
      return;
    }
    await returnToChatsHome(inst, rounds: 8);
    return;
  }
  print(
    '[${inst.name}] booting restored account '
    '${_shortId(restored.toxId)} via l3_boot_existing_account...',
  );
  await inst.bootExistingAccount(restored.toxId, restored.nickname);
  await inst.foreground();
  await inst.waitState(
    (s) => s['sessionReady'] == true,
    timeoutSecs: 60,
    label: 'restored sessionReady',
  );
  if (await _forceHomeRootAndWait(
    inst,
    tab: 'chats',
    label: 'restored boot',
    ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
  )) {
    return;
  }
  await returnToChatsHome(inst, rounds: 8);
}

class _RestoredAccount {
  _RestoredAccount({required this.toxId, required this.nickname});

  final String toxId;
  final String nickname;
}

class _RestoredPair {
  _RestoredPair({required this.a, required this.b});

  final _RestoredAccount a;
  final _RestoredAccount b;

  static Future<_RestoredPair> load() async {
    final root =
        jsonDecode(
              await File(
                'tool/mcp_test/.multi_instance_runtime/pair.json',
              ).readAsString(),
            )
            as Map<String, dynamic>;
    final instances =
        ((((root['fixture_restore'] as Map?)?['restored'] as Map?)?['instances']
                    as Map?) ??
                const <String, dynamic>{})
            .cast<String, dynamic>();
    _RestoredAccount parse(String name) {
      final raw =
          (instances[name] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final toxId = raw['tox_id']?.toString() ?? '';
      final nickname = raw['nickname']?.toString() ?? '';
      if (toxId.isEmpty || nickname.isEmpty) {
        throw DriveError('restored pair metadata missing for $name: $raw');
      }
      return _RestoredAccount(toxId: toxId, nickname: nickname);
    }

    return _RestoredPair(a: parse('A'), b: parse('B'));
  }
}

Future<bool> _tryTapText(Inst inst, String text) async {
  for (var i = 0; i < 3; i++) {
    try {
      await inst.tapText(text, retries: 1);
      return true;
    } on DriveError {
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
  return false;
}

Future<bool> _isFriendProfileShell(Inst inst) async {
  return await inst.waitKey(
        'user_profile_delete_friend_button',
        timeoutSecs: 1,
      ) ||
      await inst.waitKey('user_profile_friend_name_text', timeoutSecs: 1) ||
      await inst.waitKey('friend_profile_send_message_tile', timeoutSecs: 1) ||
      await inst.waitKey(
        'friend_profile_send_message_button',
        timeoutSecs: 1,
      ) ||
      await inst.waitText('Add Friend', timeoutSecs: 1);
}

Future<bool> _recoverFriendProfileToContacts(Inst inst) async {
  if (!await _isFriendProfileShell(inst)) return false;
  if (await _selectContactsTab(inst) || await _tryTapText(inst, 'Back')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    return true;
  }
  return false;
}

Future<bool> _isProfileQrOverlay(Inst inst) async {
  return await inst.waitKey('profile_tox_id_copy_button', timeoutSecs: 1) ||
      await inst.waitKey('profile_qr_copy_button', timeoutSecs: 1) ||
      (await inst.waitText('Save Image', timeoutSecs: 1) &&
          await inst.waitText(
            'Scan QR code to add me as contact',
            timeoutSecs: 1,
          ));
}

Future<bool> _dismissProfileQrOverlay(Inst inst) async {
  if (!await _isProfileQrOverlay(inst)) return false;
  try {
    await inst.osaEscape();
  } on DriveError {
    // Fall back to the top-right close button if the overlay ignores ESC.
  }
  await Future<void>.delayed(const Duration(milliseconds: 700));
  if (!await _isProfileQrOverlay(inst)) return true;
  await inst.tapAt(1056, 174);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return true;
}

Future<bool> _recoverActiveConversation(Inst inst) async {
  final st = await inst.dumpState();
  if (st['currentConversation'] == null) return false;
  try {
    await inst.clearActiveConversation();
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN clearActiveConversation unavailable on '
      'non-test account; falling back to UI recovery',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return true;
}

Future<bool> _recoverBlankHomeRoot(Inst inst) async {
  final st = await inst.dumpState();
  if (st['sessionReady'] != true || st['currentConversation'] != null) {
    return false;
  }
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: 1,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: 1,
  );
  if (hasBack || hasChatsSidebar || hasContactsSidebar) {
    return false;
  }
  print(
    '[${inst.name}] blank shell detected '
    '(sessionReady=true, currentConversation=null, no Back/sidebar) '
    '-> forcing HomePage root',
  );
  try {
    await inst.forceHomeRoot(tab: 'chats');
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN forceHomeRoot unavailable on non-test account '
      'during blank-shell recovery',
    );
    return false;
  }
  await Future<void>.delayed(const Duration(milliseconds: 1500));
  return true;
}

Future<bool> _contactsHomeReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  final shellTab = st['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'contacts') {
    return false;
  }
  if (st['sessionReady'] != true ||
      st['homeShellInContactProfileContext'] == true) {
    return false;
  }
  if (await inst.waitText('Back', timeoutSecs: timeoutSecs)) {
    return false;
  }
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: timeoutSecs,
  );
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: timeoutSecs,
  );
  final hasContactsLanding =
      await inst.waitKey('contact_new_contacts_tab', timeoutSecs: timeoutSecs) ||
      await inst.waitText('New Contacts', timeoutSecs: timeoutSecs);
  return hasContactsSidebar && (hasNewEntry || hasContactsLanding);
}

Future<bool> _newEntryShellReady(Inst inst, {int timeoutSecs = 1}) async {
  return _contactsHomeReady(inst, timeoutSecs: timeoutSecs);
}

Future<bool> _chatsHomeReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  final shellTab = st['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'chats') {
    return false;
  }
  if (await inst.waitText('Back', timeoutSecs: timeoutSecs)) {
    return false;
  }
  if (st['sessionReady'] != true ||
      st['homeShellInContactProfileContext'] == true) {
    return false;
  }
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: timeoutSecs,
  );
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: timeoutSecs,
  );
  return hasChatsSidebar &&
      (st['currentConversation'] == null || hasNoConversation);
}

Future<bool> _forceHomeRootAndWait(
  Inst inst, {
  required String tab,
  required String label,
  required Future<bool> Function() ready,
}) async {
  final sw = Stopwatch()..start();
  try {
    await inst.forceHomeRoot(tab: tab);
  } on DriveError catch (e) {
    print(
      '[${inst.name}] WARN forceHomeRoot($tab) failed during $label: '
      '${e.message}',
    );
    return false;
  }
  final deadline = DateTime.now().add(const Duration(seconds: 6));
  var ok = false;
  while (DateTime.now().isBefore(deadline)) {
    if (await ready()) {
      ok = true;
      break;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  final shellTab = await _homeShellTab(inst);
  print(
    '[${inst.name}] forceHomeRoot($tab) during $label '
    '=> ready=$ok after ${sw.elapsedMilliseconds}ms '
    '(homeShellTab=${shellTab ?? 'unknown'})',
  );
  return ok;
}

Future<bool> _selectChatsTab(Inst inst) async {
  if (await inst.tryTapKey('sidebar_chats_tab', retries: 2)) {
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  if (await _tryTapText(inst, 'Chats')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (await _chatsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  final sidebarVisible =
      await inst.waitKey('sidebar_chats_tab', timeoutSecs: 1) ||
      await inst.waitKey('sidebar_contacts_tab', timeoutSecs: 1);
  if (!sidebarVisible) {
    return false;
  }
  await inst.tapAt(_sidebarTabX, _sidebarChatsY);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return _chatsHomeReady(inst, timeoutSecs: 2);
}

Future<bool> _selectContactsTab(Inst inst) async {
  if (await inst.tryTapKey('sidebar_contacts_tab', retries: 2)) {
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  if (await _tryTapText(inst, 'Contacts')) {
    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (await _contactsHomeReady(inst, timeoutSecs: 2)) {
      return true;
    }
  }
  final sidebarVisible =
      await inst.waitKey('sidebar_contacts_tab', timeoutSecs: 1) ||
      await inst.waitKey('sidebar_chats_tab', timeoutSecs: 1);
  if (!sidebarVisible) {
    return false;
  }
  await inst.tapAt(_sidebarTabX, _sidebarContactsY);
  await Future<void>.delayed(const Duration(milliseconds: 900));
  return _contactsHomeReady(inst, timeoutSecs: 2);
}

/// B drives the add-friend dialog targeting A's tox id (real UI).
Future<void> driveAddFriend(Inst b, String toxA, {String? message}) async {
  await ensureNewEntryShell(b);
  var dialogReady = false;
  for (var attempt = 0; attempt < 3; attempt++) {
    if (!await b.tryTapKey('new_entry_menu_button', retries: 2) &&
        !await b.tryTapKey('contact_app_bar_menu_button', retries: 2)) {
      if (!await _tryTapText(b, 'New Chat')) {
        await b.tapAt(1236, 34);
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (!await b.tryTapKey('new_entry_add_contact_item', retries: 2) &&
        !await b.tryTapKey('contact_app_bar_add_contact_item', retries: 2) &&
        !await _tryTapText(b, 'Add Contact')) {
      continue;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await b.waitKey('add_friend_id_input', timeoutSecs: 3)) {
      dialogReady = true;
      break;
    }
  }
  if (!dialogReady) {
    await b.shot('/tmp/add_friend_dialog_${b.name}.png');
    throw DriveError('[${b.name}] add-friend dialog did not open');
  }
  await b.focusType('add_friend_id_input', toxA);
  if (message != null && message.isNotEmpty) {
    await Future<void>.delayed(const Duration(milliseconds: 250));
    await b.focusType('add_friend_message_input', message);
  }
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
  await ensureContactsShell(a);
  await a.foreground();
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
      return apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final userId = app['userId'].toString();
  print(
    '[${a.name}] application present (userId=${userId.substring(0, 16)}...)',
  );
  await _refreshApplicationList(a, userId, detail: false);
  final keyBase = accept
      ? 'contact_application_accept_button'
      : 'contact_application_decline_button';
  var tapped = await a.tryTapKey('$keyBase:$userId', retries: 2);
  if (!tapped) {
    tapped = await _tapApplicationActionByCoordinate(a, accept: accept);
  }
  // Prefer the keyed control; fall back to the visible Accept/Decline label.
  if (!tapped) {
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
  await ensureContactsShell(a);
  await a.foreground();
  if (!await a.tryTapKey('contact_new_contacts_tab')) {
    await a.tapText('New Contacts');
    await a.tapAt(240, 173);
  }
  // Wait for B's application to arrive in the model.
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final userId = app['userId'].toString();
  print(
    '[${a.name}] application present (userId=${userId.substring(0, 16)}...)',
  );
  await _refreshApplicationList(a, userId, detail: true);
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

Future<void> _refreshApplicationList(
  Inst a,
  String userId, {
  required bool detail,
}) async {
  await a.foreground();
  final probeKey = detail
      ? 'contact_application_item:$userId'
      : 'contact_application_accept_button:$userId';
  for (var attempt = 0; attempt < 3; attempt++) {
    // The New Contacts detail panel does not live-refresh reliably when the
    // inbound request lands while it is already open. Force a fresh load by
    // navigating away and back.
    await a.tapAt(240, 270); // Blocked Users master row
    await Future<void>.delayed(Duration(milliseconds: detail ? 1200 : 700));
    await a.tapAt(240, 173); // New Contacts master row (fresh load)
    await Future<void>.delayed(Duration(milliseconds: detail ? 1800 : 1200));
    if (await a.waitKey(probeKey, timeoutSecs: 4)) return;
  }
}

Future<bool> _tapApplicationActionByCoordinate(
  Inst a, {
  required bool accept,
}) async {
  await a.foreground();
  // First application row action buttons in the 1280x768 desktop layout.
  await a.tapAt(accept ? 1088 : 1170, 208);
  await Future<void>.delayed(const Duration(milliseconds: 700));
  return true;
}

Future<bool> areFriends(Inst x, String otherTox) async {
  final s = await x.dumpState();
  final friends = (s['friends'] as List?) ?? const [];
  return friends.any(
    (f) =>
        f is Map && _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox),
  );
}

Future<String> friendNick(Inst x, String otherTox) async {
  final s = await x.dumpState();
  for (final f in (s['friends'] as List? ?? const [])) {
    if (f is Map &&
        _pubkey(f['userId']?.toString() ?? '') == _pubkey(otherTox)) {
      return f['nickName']?.toString() ?? '';
    }
  }
  return '';
}

String _normalizeNick(String value) => value.trim();

String _shortId(String id) => id.length <= 16 ? id : id.substring(0, 16);

Future<void> openFriendProfile(Inst inst, String otherTox) async {
  await inst.foreground();
  await ensureContactsShell(inst);
  final fullId = otherTox.trim();
  final shortId = _pubkey(otherTox);
  final fullKey = 'contact_list_item:$fullId';
  final shortKey = 'contact_list_item:$shortId';
  for (var attempt = 0; attempt < 3; attempt++) {
    final tapped =
        await inst.tryTapKey(fullKey, retries: 2) ||
        await inst.tryTapKey(shortKey, retries: 2);
    if (!tapped) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      continue;
    }
    final onProfile =
        await inst.waitKey('user_profile_friend_name_text', timeoutSecs: 6) ||
        await inst.waitKey(
          'friend_profile_send_message_button',
          timeoutSecs: 6,
        ) ||
        await inst.waitKey('user_profile_delete_friend_button', timeoutSecs: 6);
    if (!onProfile) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
      continue;
    }
    if (await inst.waitKey(
      'user_profile_delete_friend_button',
      timeoutSecs: 10,
    )) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 900));
  }
  throw DriveError(
    '[${inst.name}] friend profile did not render delete button for '
    '${_shortId(shortId)}...',
  );
}

Future<bool> deleteFriendViaProfile(Inst inst, String otherTox) async {
  if (!await areFriends(inst, otherTox)) return false;
  await openFriendProfile(inst, otherTox);
  if (!await inst.tryTapKey('user_profile_delete_friend_button')) {
    await inst.tapText('Delete');
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  return true;
}

Future<bool> waitFriendshipState(
  Inst a,
  Inst b,
  String toxA,
  String toxB, {
  required bool friends,
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final aHasB = await areFriends(a, toxB);
    final bHasA = await areFriends(b, toxA);
    if (friends) {
      if (aHasB && bHasA) return true;
    } else if (!aHasB && !bHasA) {
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<int> runResetFriendship(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final stateA = await a.dumpState();
  final stateB = await b.dumpState();
  if (stateA['sessionReady'] != true) {
    await ensureHome(a, nickA);
  }
  if (stateB['sessionReady'] != true) {
    await ensureHome(b, nickB);
  }
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for reset: A=$toxA B=$toxB');
  }
  final aHasB = await areFriends(a, toxB);
  final bHasA = await areFriends(b, toxA);
  if (!aHasB && !bHasA) {
    print('[pair] reset_friendship no-op: pair already not friends');
    return 0;
  }
  if (aHasB) {
    await deleteFriendViaProfile(a, toxB);
  }
  if (!await waitFriendshipState(
        a,
        b,
        toxA,
        toxB,
        friends: false,
        timeoutSecs: 12,
      ) &&
      await areFriends(b, toxA)) {
    await deleteFriendViaProfile(b, toxA);
  }
  final cleared = await waitFriendshipState(
    a,
    b,
    toxA,
    toxB,
    friends: false,
    timeoutSecs: 20,
  );
  if (cleared) {
    try {
      await returnToChatsHome(a);
      await returnToChatsHome(b);
    } on DriveError catch (e) {
      print(
        '[pair] WARN: friendship reset succeeded but home recovery failed: ${e.message}',
      );
    }
    print('[pair] PASS: friendship reset both directions');
    return 0;
  }
  print(
    '[pair] FAIL: friendship reset incomplete '
    '(A has B=${await areFriends(a, toxB)} B has A=${await areFriends(b, toxA)})',
  );
  return 1;
}

Future<int> runCustomMessage(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for custom_message: A=$toxA B=$toxB');
  }
  if (await areFriends(a, toxB) || await areFriends(b, toxA)) {
    throw DriveError('custom_message requires a no-friend pair');
  }
  final wording = 'S54-CUSTOM-${DateTime.now().microsecondsSinceEpoch}';
  await driveAddFriend(b, toxA, message: wording);
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any(
        (e) =>
            e is Map &&
            _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB) &&
            (e['wording']?.toString() ?? '') == wording,
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication wording from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final seenWording = app['wording']?.toString() ?? '';
  if (seenWording != wording) {
    print('[pair] FAIL: custom message mismatch "$seenWording" != "$wording"');
    return 1;
  }
  await _refreshApplicationList(a, toxB, detail: false);
  final wordingKey = 'contact_application_addwording:${toxB.trim()}';
  await a.waitKey(wordingKey, timeoutSecs: 6);
  await driveRespondToApplication(a, toxB, accept: false);
  if (!await waitFriendshipState(
        a,
        b,
        toxA,
        toxB,
        friends: false,
        timeoutSecs: 20,
      ) &&
      (await areFriends(a, toxB) || await areFriends(b, toxA))) {
    print(
      '[pair] WARN: custom_message decline unexpectedly formed friendship; '
      'running reset_friendship cleanup',
    );
    final resetRc = await runResetFriendship(a, b, nickA, nickB);
    if (resetRc != 0 ||
        await areFriends(a, toxB) ||
        await areFriends(b, toxA)) {
      print('[pair] FAIL: custom_message cleanup unexpectedly formed friendship');
      return 1;
    }
  }
  print('[pair] PASS: custom message round-tripped and self-cleaned');
  return 0;
}

Future<String?> _callState(Inst inst) async {
  final s = await inst.dumpState();
  final call = (s['call'] as Map?)?.cast<String, dynamic>();
  return call?['state']?.toString();
}

Future<String?> _currentConversationId(Inst inst) async {
  final s = await inst.dumpState();
  final cur = (s['currentConversation'] as Map?)?.cast<String, dynamic>();
  return cur?['conversationID']?.toString();
}

Future<bool> _waitActiveChatPeerOnline(
  Inst inst, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    if (s['activeChatPeerOnline'] == true) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<bool> _waitCallStateAny(
  Inst inst,
  Set<String> states, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final current = await _callState(inst);
    if (current != null && states.contains(current)) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<bool> _waitCallStateAnyForegrounded(
  Inst inst,
  Set<String> states, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    await inst.foreground();
    final current = await _callState(inst);
    if (current != null && states.contains(current)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<bool> _startVoiceCallUntilRinging(
  Inst caller,
  Inst callee,
  String calleeId, {
  int attempts = 3,
  int timeoutSecs = 10,
}) async {
  final calleePubkey = _pubkey(calleeId);
  for (var attempt = 0; attempt < attempts; attempt++) {
    await openChat(
      caller,
      calleeId,
      preferConversationList: true,
      requirePeerOnline: true,
    );
    await _reopenChatFromConversationList(caller, 'c2c_$calleePubkey');
    await caller.foreground();
    await caller.tapKey('chat_call_voice_button');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (await _waitCallStateAnyForegrounded(callee, {
      'ringing',
      'incoming',
    }, timeoutSecs: timeoutSecs)) {
      return true;
    }
    final callerState = await _callState(caller);
    final calleeState = await _callState(callee);
    print(
      '[pair] WARN voice-call start retry '
      '(attempt ${attempt + 1}/$attempts '
      'callerState=$callerState calleeState=$calleeState)',
    );
    if (callerState == 'ringing' ||
        callerState == 'inCall' ||
        callerState == 'ended') {
      await caller.foreground();
      await caller.tryTapKey('call_hangup_button', retries: 2);
    }
    // Let both sides' call state settle back to idle before re-issuing the
    // next invite. The local notifier auto-resets ended -> idle after 2s, so a
    // too-fast retry can re-enter while the previous signaling call is still
    // winding down and never reach the callee.
    await _waitCallStateAny(caller, {'idle'}, timeoutSecs: 5);
    await _waitCallStateAny(callee, {'idle'}, timeoutSecs: 5);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (attempt + 1 < attempts) {
      print('[pair] retrying outgoing call after idle settle');
    }
  }
  return false;
}

Future<int> runCallVoice(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for call_voice: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] call_voice requires an existing friendship');
    return 1;
  }
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    await a.shot('/tmp/ui_call_reject_fail_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_call_reject_fail_B.png');
    print('[pair] FAIL: incoming call never reached ringing');
    print(
      '[pair] call_reject diag: '
      'A.call=${(aState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'B.call=${(bState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'A.activeChatPeerOnline=${aState['activeChatPeerOnline']} '
      'B.activeChatPeerOnline=${bState['activeChatPeerOnline']} '
      'A.currentConversation=${aState['currentConversation']} '
      'B.currentConversation=${bState['currentConversation']} '
      'A.homeShell=${aState['homeShell']} '
      'B.homeShell=${bState['homeShell']}',
    );
    return 1;
  }
  await a.foreground();
  await a.tapKey('call_accept_button');
  final inCallA = await _waitCallStateAny(a, {'inCall'});
  final inCallB = await _waitCallStateAny(b, {'inCall'});
  if (!inCallA || !inCallB) {
    print(
      '[pair] FAIL: call did not reach inCall '
      '(A=${await _callState(a)} B=${await _callState(b)})',
    );
    return 1;
  }
  await b.foreground();
  await b.tapKey('call_hangup_button');
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  await a.shot('/tmp/ui_call_voice_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_call_voice_B.png');
  if (endedA && endedB) {
    print('[pair] PASS: voice call accepted and hung up through real UI');
    return 0;
  }
  print(
    '[pair] FAIL: call did not tear down cleanly '
    '(A=${await _callState(a)} B=${await _callState(b)})',
  );
  return 1;
}

Future<int> runCallReject(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for call_reject: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] call_reject requires an existing friendship');
    return 1;
  }
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    await a.shot('/tmp/ui_call_reject_fail_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_call_reject_fail_B.png');
    print('[pair] FAIL: incoming call never reached ringing');
    print(
      '[pair] call_reject diag: '
      'A.call=${(aState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'B.call=${(bState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'A.activeChatPeerOnline=${aState['activeChatPeerOnline']} '
      'B.activeChatPeerOnline=${bState['activeChatPeerOnline']} '
      'A.currentConversation=${aState['currentConversation']} '
      'B.currentConversation=${bState['currentConversation']} '
      'A.homeShell=${aState['homeShell']} '
      'B.homeShell=${bState['homeShell']}',
    );
    return 1;
  }
  await a.foreground();
  await a.tapKey('call_decline_button');
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  await a.shot('/tmp/ui_call_reject_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_call_reject_B.png');
  if (endedA && endedB) {
    print('[pair] PASS: voice call rejected through real UI');
    return 0;
  }
  print(
    '[pair] FAIL: rejected call did not settle to idle '
    '(A=${await _callState(a)} B=${await _callState(b)})',
  );
  return 1;
}

// Logical-pixel center of the desktop composer text field (1280x768 window).
const _composerX = 830;
const _composerY = 702;

/// Open the C2C chat with [friendPubkey] (64-char) by tapping the contact tile.
Future<void> openChat(
  Inst inst,
  String friendId, {
  bool preferConversationList = true,
  bool requirePeerOnline = false,
}) async {
  await inst.foreground();
  final fullId = friendId.trim();
  final friendPubkey = _pubkey(friendId);
  final targetConversation = 'c2c_$friendPubkey';
  Future<bool> ready() async {
    if (!await _chatSurfaceReady(inst, targetConversation, timeoutSecs: 2)) {
      return false;
    }
    if (!requirePeerOnline) {
      return true;
    }
    return _waitActiveChatPeerOnline(inst, timeoutSecs: 3);
  }

  if (preferConversationList && await ready()) {
    return;
  }
  if (preferConversationList &&
      await _homeShellTab(inst) == 'chats' &&
      await _waitConversationListed(inst, targetConversation)) {
    await inst.tapKey('conversation_list_item:$targetConversation');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (await ready()) {
      return;
    }
  }
  if (preferConversationList && await _homeShellTab(inst) != 'chats') {
    await returnToChatsHome(inst, rounds: 4);
    if (await _waitConversationListed(inst, targetConversation)) {
      await inst.tapKey('conversation_list_item:$targetConversation');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (await ready()) {
        return;
      }
    }
  }
  if (preferConversationList) {
    final st = await inst.dumpState();
    final ids = (st['conversationIds'] as List?) ?? const [];
    print(
      '[${inst.name}] WARN conversation-list openChat fallback '
      'target=$targetConversation listed=${ids.contains(targetConversation)} '
      'count=${ids.length} homeShellTab=${st['homeShellTab']} '
      'currentConversation=${st['currentConversation']}',
    );
  }
  await ensureContactsShell(inst);
  final fullKey = 'contact_list_item:$fullId';
  final shortKey = 'contact_list_item:$friendPubkey';
  final tapped =
      await inst.tryTapKey(fullKey, retries: 2) ||
      await inst.tryTapKey(shortKey, retries: 2);
  if (!tapped) {
    throw DriveError(
      '[${inst.name}] contact tile not found for ${_shortId(friendPubkey)} '
      '(full=${_shortId(fullId)})',
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  if (await ready()) {
    return;
  }
  final onProfile =
      await inst.waitKey('friend_profile_send_message_tile', timeoutSecs: 4) ||
      await inst.waitKey('friend_profile_send_message_button', timeoutSecs: 4);
  if (!onProfile) {
    throw DriveError(
      '[${inst.name}] contact tap for ${_shortId(friendPubkey)} did not reach '
      'either chat or friend profile',
    );
  }
  if (!await inst.tryTapKey('friend_profile_send_message_tile', retries: 2)) {
    if (!await _tryTapText(inst, 'Send Message')) {
      // Left-most tile in the [Send Message, Voice, Video] row.
      await inst.tapAt(448, 428);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }
  if (!await ready()) {
    final st = await inst.dumpState();
    throw DriveError(
      '[${inst.name}] friend profile Send Message tile did not open chat '
      'for ${_shortId(friendPubkey)} '
      '(currentConversation=${await _currentConversationId(inst)} '
      'homeShellTab=${await _homeShellTab(inst)} '
      'activeChatPeerOnline=${st['activeChatPeerOnline']})',
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

Future<bool> _conversationListed(Inst inst, String conversationId) async {
  final s = await inst.dumpState();
  final ids = (s['conversationIds'] as List?) ?? const [];
  return ids.contains(conversationId);
}

Future<bool> _waitConversationListed(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 6,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _conversationListed(inst, conversationId)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<void> _reopenChatFromConversationList(
  Inst inst,
  String conversationId,
) async {
  if (!await _conversationListed(inst, conversationId)) {
    return;
  }
  try {
    await inst.clearActiveConversation();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN clearActiveConversation unavailable during '
      'conversation retap; continuing without reset',
    );
  }
  if (await _homeShellTab(inst) != 'chats') {
    await returnToChatsHome(inst, rounds: 4);
  }
  await inst.tapKey('conversation_list_item:$conversationId');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

Future<bool> _chatSurfaceReady(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final shellTab = await _homeShellTab(inst);
    final currentConversation = await _currentConversationId(inst);
    final hasInput = await inst.waitKey(
      'chat_input_text_field',
      timeoutSecs: 1,
    );
    if (shellTab == 'chats' &&
        currentConversation == conversationId &&
        hasInput) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

/// Type [text] into the REAL composer and send it with a REAL Return, retrying
/// the focus+Return until the conversation's last message actually becomes
/// [text] (the legacy RawKeyEvent send races a freshly-typed field, so a single
/// Return is unreliable — verify-and-retry).
Future<bool> sendComposerMessage(Inst inst, String text) async {
  for (var outer = 0; outer < 2; outer++) {
    await inst.foreground();
    // The outer `chat_input_text_field` key is a reliable presence anchor, but
    // the actual editable still focuses most reliably from a direct coordinate
    // tap inside the desktop composer.
    await inst.waitKey('chat_input_text_field', timeoutSecs: 8);
    await Future<void>.delayed(const Duration(milliseconds: 400));
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
    // Re-prime the chat surface once before giving up.
    await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'sendComposerMessage retry',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
    );
  }
  return false;
}

Future<String?> _homeShellTab(Inst inst) async {
  final s = await inst.dumpState();
  return s['homeShellTab']?.toString();
}

Future<int> runProbeHomeRoot(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for probe_home_root: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    throw DriveError('probe_home_root requires an existing friendship');
  }
  final pairs = [(a, _pubkey(toxB)), (b, _pubkey(toxA))];
  for (final pair in pairs) {
    final inst = pair.$1;
    final peerPubkey = pair.$2;
    await openChat(inst, peerPubkey);
    final contactsOk = await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'probe_home_root from active chat',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 3),
    );
    if (!contactsOk) {
      throw DriveError(
        '[${inst.name}] probe_home_root failed to reach contacts root',
      );
    }
    final chatsOk = await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'probe_home_root from contacts root',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
    );
    if (!chatsOk) {
      throw DriveError(
        '[${inst.name}] probe_home_root failed to reach chats root',
      );
    }
  }
  await a.shot('/tmp/ui_probe_home_root_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_probe_home_root_B.png');
  print(
    '[pair] PASS: l3_force_home_root restored contacts/chats on both peers',
  );
  return 0;
}

Future<bool> _sendAndWait(
  Inst sender,
  Inst receiver,
  String receiverPubkey,
  String text, {
  int timeoutSecs = 60,
}) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    await openChat(sender, receiverPubkey);
    final sent = await sendComposerMessage(sender, text);
    final received = await _waitLastMessage(
      receiver,
      text,
      timeoutSecs: timeoutSecs,
    );
    if (sent && received) return true;
    print(
      '[pair] WARN sendAndWait retry for "$text" '
      '(attempt ${attempt + 1}/2 sent=$sent recv=$received '
      'senderConv=${await _currentConversationId(sender)} '
      'receiverLast=${await _lastMessage(receiver)})',
    );
    await sender.shot('/tmp/send_fail_${sender.name}_${attempt + 1}.png');
    await receiver.foreground();
    await receiver.shot('/tmp/send_fail_${receiver.name}_${attempt + 1}.png');
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

Future<bool> _waitLastMessage(
  Inst inst,
  String text, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _lastMessage(inst) == text) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

/// S62/S64: bidirectional message delivery driven through the REAL composer
/// across two processes. Assumes A and B are already friends.
Future<int> runMessage(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
  int stamp,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final bobPk = _pubkey(toxB);
  final alicePk = _pubkey(toxA);
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print(
      '[pair] message scenario requires an existing friendship; run handshake first',
    );
    return 1;
  }
  final m1 = 'RUITEST-AtoB-$stamp';
  final m2 = 'RUITEST-BtoA-$stamp';

  final aOk = await _sendAndWait(a, b, bobPk, m1, timeoutSecs: 60);
  final bGot = await _waitLastMessage(b, m1, timeoutSecs: 2);
  print('[pair] A->B sent=$aOk received=$bGot ("$m1")');

  final bOk = await _sendAndWait(b, a, alicePk, m2, timeoutSecs: 60);
  final aGot = await _waitLastMessage(a, m2, timeoutSecs: 2);
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

Future<int> runMessageBurst(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] message_burst requires an existing friendship');
    return 1;
  }
  final bobPk = _pubkey(toxB);
  final alicePk = _pubkey(toxA);
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final aMsgs = [
    'RUIBURST-A1-$nonce',
    'RUIBURST-A2-$nonce',
    'RUIBURST-A3-$nonce',
  ];
  final bMsgs = [
    'RUIBURST-B1-$nonce',
    'RUIBURST-B2-$nonce',
    'RUIBURST-B3-$nonce',
  ];

  for (var i = 0; i < aMsgs.length; i++) {
    final aOk = await _sendAndWait(a, b, bobPk, aMsgs[i], timeoutSecs: 60);
    final bGot = await _waitLastMessage(b, aMsgs[i], timeoutSecs: 2);
    if (!aOk || !bGot) {
      print('[pair] FAIL: burst A->$i did not converge');
      return 1;
    }
    final bOk = await _sendAndWait(b, a, alicePk, bMsgs[i], timeoutSecs: 60);
    final aGot = await _waitLastMessage(a, bMsgs[i], timeoutSecs: 2);
    if (!bOk || !aGot) {
      print('[pair] FAIL: burst B->$i did not converge');
      return 1;
    }
  }

  await a.shot('/tmp/ui_message_burst_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_message_burst_B.png');
  print('[pair] PASS: alternating real-UI burst converged both directions');
  return 0;
}

Future<void> main(List<String> args) async {
  exitCode = await HttpOverrides.runWithHttpOverrides(
    () => _main(args),
    _LocalVmServiceHttpOverrides(),
  );
}

Future<int> _main(List<String> args) async {
  final positional = <String>[];
  var bootRestored = false;
  for (final arg in args) {
    if (arg == '--boot-restored') {
      bootRestored = true;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 7) {
    print(
      'usage: drive_real_ui_pair.dart <scenario> '
      '<wsA> <pidA> <nickA> <wsB> <pidB> <nickB>',
    );
    return 64;
  }
  final scenario = positional[0];
  final a = Inst('A', positional[1], int.parse(positional[2]));
  final nickA = positional[3];
  final b = Inst('B', positional[4], int.parse(positional[5]));
  final nickB = positional[6];
  await a.connect();
  await b.connect();
  try {
    _RestoredPair? restored;
    if (bootRestored) {
      restored = await _RestoredPair.load();
      await _ensureRestoredHome(a, restored.a);
      await _ensureRestoredHome(b, restored.b);
    }
    if (scenario == 'reset_friendship') {
      return await runResetFriendship(a, b, nickA, nickB);
    }
    if (scenario == 'custom_message') {
      return await runCustomMessage(a, b, nickA, nickB);
    }
    if (scenario == 'message') {
      // Stamp passed via env (scripts can't use DateTime determinism concerns here).
      final stamp =
          int.tryParse(Platform.environment['RUITEST_STAMP'] ?? '') ??
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return await runMessage(a, b, nickA, nickB, stamp);
    }
    if (scenario == 'message_burst') {
      return await runMessageBurst(a, b, nickA, nickB);
    }
    if (scenario == 'probe_home_root') {
      return await runProbeHomeRoot(a, b, nickA, nickB);
    }
    if (scenario == 'call_voice') {
      return await runCallVoice(a, b, nickA, nickB);
    }
    if (scenario == 'call_reject') {
      return await runCallReject(a, b, nickA, nickB);
    }
    if (!bootRestored) {
      final needsNoFriendFlow =
          scenario == 'handshake' ||
          scenario == 'handshake_detail' ||
          scenario == 'decline';
      await ensureHome(a, nickA, requireHomeMenu: !needsNoFriendFlow);
      if (needsNoFriendFlow) {
        await ensureHome(b, nickB, requireHomeMenu: false);
        await ensureNewEntryShell(b);
      } else {
        await ensureHome(b, nickB);
      }
    }

    final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
    final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
    if (toxA.isEmpty || toxB.isEmpty) {
      throw DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[pair] toxA=${toxA.substring(0, 16)}.. toxB=${toxB.substring(0, 16)}..',
    );

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
      await a.waitState((_) => true, timeoutSecs: 1);
      final aHasB = await _retryBool(
        () => areFriends(a, toxB),
        label: 'A has B as friend',
      );
      final bHasA = await _retryBool(
        () => areFriends(b, toxA),
        label: 'B has A as friend',
      );
      // Name-propagation regression gate (the register-time setSelfInfo bug):
      // each peer must see the OTHER's registered nickname, not the raw tox-id.
      final aSeesNick = await _retryBool(
        () async =>
            _normalizeNick(await friendNick(a, toxB)) == _normalizeNick(nickB),
        label: 'A sees B nickname "$nickB"',
        attempts: 60,
      );
      final bSeesNick = await _retryBool(
        () async =>
            _normalizeNick(await friendNick(b, toxA)) == _normalizeNick(nickA),
        label: 'B sees A nickname "$nickA"',
        attempts: 60,
      );
      final aSeesNickNow =
          _normalizeNick(await friendNick(a, toxB)) == _normalizeNick(nickB);
      final bSeesNickNow =
          _normalizeNick(await friendNick(b, toxA)) == _normalizeNick(nickA);
      final finalASeesNick = aSeesNick || aSeesNickNow;
      final finalBSeesNick = bSeesNick || bSeesNickNow;
      print(
        '[pair] names: A sees B="${await friendNick(a, toxB)}" '
        'B sees A="${await friendNick(b, toxA)}"',
      );
      await a.shot('/tmp/ui_${scenario}_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_${scenario}_B.png');
      if (aHasB && bHasA && finalASeesNick && finalBSeesNick) {
        print('[pair] PASS: friendship + name propagation both directions');
        return 0;
      }
      print(
        '[pair] FAIL: aHasB=$aHasB bHasA=$bHasA '
        'aSeesNick=$finalASeesNick bSeesNick=$finalBSeesNick',
      );
      return 1;
    } else {
      // Decline: application should clear on A and no friendship forms.
      await Future<void>.delayed(const Duration(seconds: 3));
      final stillFriend = await areFriends(a, toxB);
      final apps =
          ((await a.dumpState())['friendApplications'] as List?) ?? const [];
      final appGone = !apps.any(
        (e) =>
            e is Map && _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
      );
      await a.shot('/tmp/ui_${scenario}_A.png');
      if (!stillFriend && appGone) {
        print('[pair] PASS: decline removed application, no friendship');
        return 0;
      }
      print('[pair] FAIL: stillFriend=$stillFriend appGone=$appGone');
      return 1;
    }
  } on PermissionBlockedError catch (e) {
    print('[pair] BLOCKED: ${e.message}');
    return 78;
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
