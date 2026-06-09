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
//   group_message     S151 — with an existing friendship, A creates a PRIVATE
//                     group and invites B (who auto-joins over the friend link),
//                     then both sides send through the REAL group composer. On
//                     test accounts this drives the l3 setup tools; on fresh
//                     non-test accounts it falls back to the REAL add-group
//                     dialog + add-member screen + ungated plumbing hooks (the
//                     l3 create/invite/setting/member-list/leave tools are
//                     test-gated).
//   group_create      S126/S127/S128/S129/S130 — single-instance: A opens the
//                     REAL add-group dialog, creates a group, opens the new
//                     group conversation, and sends one message through the
//                     REAL composer (own-sent bubble renders). No second peer —
//                     a fast surface check distinct from group_message delivery.
//   conference_message S156/S159/S160/S177/S181 — same two-process shape as
//                     group_message but a LEGACY Tox CONFERENCE (created via the
//                     Conference dialog type; C++ InviteUserToGroup branches to
//                     tox_conference_invite, B auto-joins via tox_conference_join).
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
import 'fixture_c_bootstrap.dart';

const _skillNs = 'ext.flutter.flutter_skill';
const _mcpNs = 'ext.mcp.toolkit';
const _sidebarTabX = 50;
const _sidebarChatsY = 220;
const _sidebarContactsY = 288;

class _LocalVmServiceHttpOverrides extends HttpOverrides {
  @override
  String findProxyFromEnvironment(Uri url, Map<String, String>? environment) {
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
  String ws;
  final int pid;
  late VmService vm;
  late String iso;

  /// Latches true once an l3 navigation tool (e.g. l3_force_home_root) reports
  /// `non_test_account`. An account REGISTERED through the real UI (every fresh
  /// no-friend launch) carries no l3 seed marker, so the mutating nav tools are
  /// refused and each call is dead weight. Shell recovery consults this to skip
  /// the doomed call (and its WARN) instead of burning a recovery round on it.
  bool navToolsUnavailable = false;

  Future<void> connect() async {
    await _refreshWsUriFromRuntime();
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
        await _refreshWsUriFromRuntime();
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

  Future<void> waitExt(String name, {int timeoutSecs = 60}) =>
      _waitExt(name, timeoutSecs: timeoutSecs);

  Future<void> _reconnect() async {
    print('[$name] VM service connection dropped — reconnecting $ws');
    try {
      await vm.dispose();
    } catch (_) {}
    await _refreshWsUriFromRuntime();
    await _connectVmWithRetry();
  }

  Future<void> _refreshWsUriFromRuntime() async {
    try {
      final pairFile = File('tool/mcp_test/.multi_instance_runtime/pair.json');
      if (!await pairFile.exists()) return;
      final root =
          jsonDecode(await pairFile.readAsString()) as Map<String, dynamic>;
      final instances =
          (root['instances'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      Map<String, dynamic>? match;
      for (final entry in instances.values) {
        if (entry is! Map) continue;
        final map = entry.cast<String, dynamic>();
        final entryPid = int.tryParse('${map['pid']}');
        if (entryPid == pid) {
          match = map;
          break;
        }
      }
      if (match == null) return;
      final stdioLogPath = match['stdio_log']?.toString();
      if (stdioLogPath == null || stdioLogPath.isEmpty) return;
      final stdioFile = File(stdioLogPath);
      if (!await stdioFile.exists()) return;
      final lines = await stdioFile.readAsLines();
      String? latestVmHttp;
      final vmLinePattern = RegExp(
        r'http://127\.0\.0\.1:\d+(?:/[A-Za-z0-9_=-]+)?/?',
      );
      for (final line in lines.reversed) {
        final match = vmLinePattern.firstMatch(line);
        if (match != null) {
          latestVmHttp = match.group(0);
          break;
        }
      }
      if (latestVmHttp == null || latestVmHttp.isEmpty) return;
      latestVmHttp = latestVmHttp.replaceFirst(RegExp(r'/$'), '');
      final refreshedWs = '${latestVmHttp.replaceFirst('http:', 'ws:')}/ws';
      if (refreshedWs != ws) {
        print(
          '[$name] refreshed VM service URI from runtime: $ws -> $refreshedWs',
        );
        ws = refreshedWs;
      }
    } catch (e) {
      print('[$name] WARN could not refresh VM URI from runtime: $e');
    }
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

  Future<Map<String, dynamic>> dumpState({
    String? userId,
    String? conversationId,
  }) => l3('l3_dump_state', {
    if (userId != null) 'userId': userId,
    if (conversationId != null) 'conversationId': conversationId,
  });

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
      if (r['error'] == 'non_test_account') navToolsUnavailable = true;
      throw DriveError('[$name] l3_force_home_root failed: $r');
    }
  }

  Future<bool> openAddFriendDialogViaL3() async {
    final r = await l3('l3_open_add_friend_dialog');
    return r['ok'] == true;
  }

  Future<bool> deleteFriendViaL3(String userId) async {
    final r = await l3('l3_delete_friend', {'userId': userId});
    return r['ok'] == true;
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

  /// SINGLE-FIRE tap on a keyed element: resolve its on-screen centre via
  /// `interactiveStructured` and dispatch exactly ONE `tapAt`.
  ///
  /// flutter_skill's `tap` fires the callback TWICE — once via a synthetic
  /// pointer (`_dispatchTap`) and again via a direct `widget.onPressed!()`
  /// (`_tryInvokeCallback`). For a route-popping button (`Navigator.pop(...)`)
  /// that means TWO pops: the first closes the dialog, the second — invoked
  /// while the button is still mounted mid-dismiss — pops the PAGE underneath.
  /// In the logout/password flows that pops HomePage, and the trailing
  /// `if (!mounted) return` then skips the `pushAndRemoveUntil(LoginPage)`,
  /// leaving an EMPTY Navigator (blank screen, zero interactive elements). Use
  /// this for the ON-SCREEN dialog POP buttons (confirm/save/dismiss). NOT for
  /// below-fold openers — a coordinate `tapAt` would miss; drive those with
  /// `tapKey`, whose direct `_tryInvokeCallback` fires once off-screen. See the
  /// flutter_skill_double_tap_blank harness hazard. Returns false (no throw)
  /// when the key is absent or has no usable bounds.
  Future<bool> tapKeyCenter(String key, {int timeoutSecs = 8}) async {
    if (!await waitKey(key, timeoutSecs: timeoutSecs)) return false;
    // `waitKey` proves the element is in the tree, but not that it has been
    // LAID OUT: in the one-frame window after a dialog appears the RenderBox can
    // still be absent, so interactiveStructured reports {x:0,y:0,w:0,h:0}.
    // Re-query a few times so a not-yet-measured button isn't mistaken for
    // "not tappable" (a silent hard-gate failure). The happy path taps on the
    // first attempt, unchanged.
    for (var attempt = 0; attempt < 5; attempt++) {
      final r = await skill('interactiveStructured', const {});
      final data = r['data'];
      final elements = data is Map ? data['elements'] : null;
      if (elements is List) {
        // Scan ALL same-key matches and tap the first with positive bounds — a
        // stale/offstage earlier match (e.g. a stacked dialog or an IndexedStack
        // branch) must not mask a later visible copy.
        for (final e in elements) {
          if (e is! Map || e['key'] != key) continue;
          final b = e['bounds'];
          if (b is! Map) continue;
          final x = (b['x'] as num?) ?? 0;
          final y = (b['y'] as num?) ?? 0;
          final w = (b['w'] as num?) ?? 0;
          final h = (b['h'] as num?) ?? 0;
          if (w <= 0 || h <= 0) continue; // unsized/off-screen — try next match
          await tapAt(x + w / 2, y + h / 2);
          return true;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return false;
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
      // flutter_skill's waitForElement timeout is MILLISECONDS
      // (Duration(milliseconds: timeout)). Passing the bare seconds value made
      // every wait a ~Nms single check that only "worked" when the element was
      // already present; a wait on a freshly-triggered async open (e.g. a
      // showDialog field) expired before the first frame. Convert to ms so
      // timeoutSecs actually means seconds.
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['found'] == true;
  }

  Future<bool> waitText(String text, {int timeoutSecs = 25}) async {
    final r = await skill('waitForElement', {
      'text': text,
      // See waitKey: flutter_skill expects the timeout in milliseconds.
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['found'] == true;
  }

  /// Poll until a keyed widget is GONE (dialog closed / page changed), via
  /// flutter_skill's purpose-built `waitForGone` (timeout in ms, like waitKey).
  Future<bool> waitKeyGone(String key, {int timeoutSecs = 8}) async {
    final r = await skill('waitForGone', {
      'key': key,
      'timeout': '${timeoutSecs * 1000}',
    });
    return r['gone'] == true;
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
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-chats snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'profileContext=${st['homeShellInContactProfileContext']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasChatsSidebar=$hasChatsSidebar hasContactsSidebar=$hasContactsSidebar '
    'hasNoConversation=$hasNoConversation '
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
      label: 'ensureNewEntryShell',
      ready: () => _newEntryShellReady(inst, timeoutSecs: 2),
    )) {
      return;
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
  final hasBack = await inst.waitText('Back', timeoutSecs: 1);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: 1,
  );
  final hasContactAppBarMenu = await inst.waitKey(
    'contact_app_bar_menu_button',
    timeoutSecs: 1,
  );
  final hasContactAppBarTrailing = await inst.waitKey(
    'contact_app_bar_trailing_override',
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
  final hasContactsLanding =
      await inst.waitKey('contact_new_contacts_tab', timeoutSecs: 1) ||
      await inst.waitText('New Contacts', timeoutSecs: 1);
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: 1,
  );
  await inst.shot(shotPath);
  print(
    '[${inst.name}] recover-new-entry snapshot: '
    'sessionReady=${st['sessionReady']} '
    'friendCount=${st['friendCount']} '
    'friendApplicationCount=${st['friendApplicationCount']} '
    'currentConversation=${st['currentConversation']} '
    'homeShellTab=${st['homeShellTab']} '
    'homeShellCurrentConversationId=${st['homeShellCurrentConversationId']} '
    'profileContext=${st['homeShellInContactProfileContext']} '
    'hasBack=$hasBack hasNewEntry=$hasNewEntry '
    'hasContactAppBarMenu=$hasContactAppBarMenu '
    'hasContactAppBarTrailing=$hasContactAppBarTrailing '
    'hasChatsSidebar=$hasChatsSidebar '
    'hasContactsSidebar=$hasContactsSidebar '
    'hasContactsLanding=$hasContactsLanding '
    'hasNoConversation=$hasNoConversation '
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
      await inst.waitKey(
        'contact_new_contacts_tab',
        timeoutSecs: timeoutSecs,
      ) ||
      await inst.waitText('New Contacts', timeoutSecs: timeoutSecs);
  return hasContactsSidebar && (hasNewEntry || hasContactsLanding);
}

Future<bool> _newEntryShellReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  final keyTimeoutSecs = timeoutSecs <= 1 ? timeoutSecs : 1;
  final hasBack = await inst.waitText('Back', timeoutSecs: keyTimeoutSecs);
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactAppBarMenu = await inst.waitKey(
    'contact_app_bar_menu_button',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactAppBarTrailing = await inst.waitKey(
    'contact_app_bar_trailing_override',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactsSidebar = await inst.waitKey(
    'sidebar_contacts_tab',
    timeoutSecs: keyTimeoutSecs,
  );
  final hasContactsLanding =
      await inst.waitKey(
        'contact_new_contacts_tab',
        timeoutSecs: keyTimeoutSecs,
      ) ||
      await inst.waitText('New Contacts', timeoutSecs: keyTimeoutSecs);
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: keyTimeoutSecs,
  );
  return _newEntryShellLandmarksAreUsable(
    state: st,
    hasBack: hasBack,
    hasNewEntry: hasNewEntry,
    hasContactAppBarMenu: hasContactAppBarMenu,
    hasContactAppBarTrailing: hasContactAppBarTrailing,
    hasChatsSidebar: hasChatsSidebar,
    hasContactsSidebar: hasContactsSidebar,
    hasContactsLanding: hasContactsLanding,
    hasNoConversation: hasNoConversation,
  );
}

bool _newEntryShellLandmarksAreUsable({
  required Map<String, dynamic> state,
  required bool hasBack,
  required bool hasNewEntry,
  required bool hasContactAppBarMenu,
  required bool hasContactAppBarTrailing,
  required bool hasChatsSidebar,
  required bool hasContactsSidebar,
  required bool hasContactsLanding,
  required bool hasNoConversation,
}) {
  if (state['sessionReady'] != true || hasBack) {
    return false;
  }
  final shellTab = state['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'contacts' && shellTab != 'chats') {
    return false;
  }
  final hasEntryAffordance =
      hasNewEntry || hasContactAppBarMenu || hasContactAppBarTrailing;
  if (!hasEntryAffordance) return false;
  final hasHomeLandmark =
      hasChatsSidebar ||
      hasContactsSidebar ||
      hasContactsLanding ||
      hasNoConversation;
  if (!hasHomeLandmark) return false;
  if (state['homeShellInContactProfileContext'] == true &&
      !_isStaleNoFriendHomeShell(
        state: state,
        hasContactsLanding: hasContactsLanding,
        hasNoConversation: hasNoConversation,
      )) {
    return false;
  }
  return true;
}

bool _isStaleNoFriendHomeShell({
  required Map<String, dynamic> state,
  required bool hasContactsLanding,
  required bool hasNoConversation,
}) {
  return _stateInt(state['friendCount']) == 0 &&
      (hasContactsLanding || hasNoConversation);
}

int? _stateInt(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '');
}

int _runShellRecoverySelfTest() {
  var failures = 0;

  Map<String, dynamic> state({
    required String? tab,
    bool sessionReady = true,
    bool profile = false,
    int? friendCount,
  }) => {
    'sessionReady': sessionReady,
    'homeShellTab': tab,
    'homeShellInContactProfileContext': profile,
    if (friendCount != null) 'friendCount': friendCount,
  };

  void expectUsable(
    String name,
    bool expected, {
    required Map<String, dynamic> state,
    bool hasBack = false,
    bool hasNewEntry = true,
    bool hasContactAppBarMenu = false,
    bool hasContactAppBarTrailing = false,
    bool hasChatsSidebar = false,
    bool hasContactsSidebar = false,
    bool hasContactsLanding = false,
    bool hasNoConversation = false,
  }) {
    final actual = _newEntryShellLandmarksAreUsable(
      state: state,
      hasBack: hasBack,
      hasNewEntry: hasNewEntry,
      hasContactAppBarMenu: hasContactAppBarMenu,
      hasContactAppBarTrailing: hasContactAppBarTrailing,
      hasChatsSidebar: hasChatsSidebar,
      hasContactsSidebar: hasContactsSidebar,
      hasContactsLanding: hasContactsLanding,
      hasNoConversation: hasNoConversation,
    );
    if (actual != expected) {
      failures++;
      print(
        '[self-test] FAIL $name: expected=$expected actual=$actual '
        'state=$state',
      );
    }
  }

  void expectChatsUsable(
    String name,
    bool expected, {
    required Map<String, dynamic> state,
    bool hasBack = false,
    bool hasChatsSidebar = true,
    bool hasNewEntry = true,
    bool hasNoConversation = false,
  }) {
    final actual = _chatsHomeLandmarksAreUsable(
      state: state,
      hasBack: hasBack,
      hasChatsSidebar: hasChatsSidebar,
      hasNewEntry: hasNewEntry,
      hasNoConversation: hasNoConversation,
    );
    if (actual != expected) {
      failures++;
      print(
        '[self-test] FAIL $name: expected=$expected actual=$actual '
        'state=$state',
      );
    }
  }

  expectUsable(
    'fresh chats no-friend shell with NewEntry',
    true,
    state: state(tab: 'chats'),
    hasChatsSidebar: true,
    hasNoConversation: true,
  );
  expectUsable(
    'fresh contacts shell with NewEntry',
    true,
    state: state(tab: 'contacts'),
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'stale profile flag on a no-friend home shell',
    true,
    state: state(tab: 'chats', profile: true, friendCount: 0),
    hasContactAppBarTrailing: true,
    hasChatsSidebar: true,
    hasContactsSidebar: true,
    hasContactsLanding: true,
    hasNoConversation: true,
  );
  expectUsable(
    'UIKit contacts app-bar fallback',
    true,
    state: state(tab: 'contacts'),
    hasNewEntry: false,
    hasContactAppBarMenu: true,
    hasContactsSidebar: true,
  );
  expectUsable(
    'profile route is not a reusable shell',
    false,
    state: state(tab: 'contacts', profile: true, friendCount: 1),
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'detail back route is not a reusable shell',
    false,
    state: state(tab: 'contacts'),
    hasBack: true,
    hasContactsSidebar: true,
    hasContactsLanding: true,
  );
  expectUsable(
    'settings tab is not an add-friend shell',
    false,
    state: state(tab: 'settings'),
    hasNewEntry: true,
    hasContactsSidebar: true,
  );
  expectUsable(
    'missing add-friend affordance is not reusable',
    false,
    state: state(tab: 'chats'),
    hasNewEntry: false,
    hasChatsSidebar: true,
    hasNoConversation: true,
  );
  expectChatsUsable(
    'stale no-friend conversation is reusable chats home',
    true,
    state: {
      ...state(tab: 'chats', profile: true, friendCount: 0),
      'currentConversation': {'conversationID': 'c2c_stale'},
    },
  );
  expectChatsUsable(
    'friend profile context is not chats home',
    false,
    state: {
      ...state(tab: 'chats', profile: true, friendCount: 1),
      'currentConversation': {'conversationID': 'c2c_friend'},
    },
  );

  if (failures != 0) return 1;
  print('[self-test] PASS shell recovery landmark matrix');
  return 0;
}

Future<bool> _chatsHomeReady(Inst inst, {int timeoutSecs = 1}) async {
  final st = await inst.dumpState();
  if (st['sessionReady'] != true) return false;
  final hasBack = await inst.waitText('Back', timeoutSecs: timeoutSecs);
  final hasChatsSidebar = await inst.waitKey(
    'sidebar_chats_tab',
    timeoutSecs: timeoutSecs,
  );
  final hasNewEntry = await inst.waitKey(
    'new_entry_menu_button',
    timeoutSecs: timeoutSecs,
  );
  final hasNoConversation = await inst.waitText(
    'No Conversation',
    timeoutSecs: timeoutSecs,
  );
  return _chatsHomeLandmarksAreUsable(
    state: st,
    hasBack: hasBack,
    hasChatsSidebar: hasChatsSidebar,
    hasNewEntry: hasNewEntry,
    hasNoConversation: hasNoConversation,
  );
}

bool _chatsHomeLandmarksAreUsable({
  required Map<String, dynamic> state,
  required bool hasBack,
  required bool hasChatsSidebar,
  required bool hasNewEntry,
  required bool hasNoConversation,
}) {
  if (state['sessionReady'] != true || hasBack || !hasChatsSidebar) {
    return false;
  }
  final shellTab = state['homeShellTab']?.toString();
  if (shellTab != null && shellTab != 'chats') {
    return false;
  }
  final staleNoFriendShell =
      _stateInt(state['friendCount']) == 0 && hasNewEntry;
  if (state['homeShellInContactProfileContext'] == true &&
      !staleNoFriendShell) {
    return false;
  }
  return state['currentConversation'] == null ||
      hasNoConversation ||
      staleNoFriendShell;
}

Future<bool> _forceHomeRootAndWait(
  Inst inst, {
  required String tab,
  required String label,
  required Future<bool> Function() ready,
}) async {
  if (inst.navToolsUnavailable) {
    // l3_force_home_root is refused on a freshly-registered (non-test) account;
    // skip the known-dead call so it neither WARN-spams nor burns a recovery
    // round. The UI-landmark recovery below (sidebar taps, Back, escape) and the
    // relaxed no-friend readiness handle these accounts without it.
    return false;
  }
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
  // The keyed NewEntry menu (new_entry_menu_button) lives in the CONTACTS app
  // bar. On a fresh non-test account B usually sits on the Chats home and can't
  // flip tabs via l3_force_home_root (refused). Open the real AddFriendDialog
  // straight through the tab-independent, non-blocking L3 invoker instead of
  // blind coordinate taps on the wrong tab (which can stray-open a conversation
  // and leave B in a non-reusable shell). Confirm via the dialog's input field.
  if (await _homeShellTab(b) != 'contacts' &&
      await b.openAddFriendDialogViaL3()) {
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await b.waitKey('add_friend_id_input', timeoutSecs: 3)) {
      dialogReady = true;
    }
  }
  for (var attempt = 0; attempt < 3 && !dialogReady; attempt++) {
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
      // Fixed desktop fallback: both toxee's NewEntryButton menu and UIKit's
      // default contacts app-bar menu anchor in the top-right corner and place
      // "Add Contact" as the first row directly below the trigger.
      await b.tapAt(1156, 88);
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
    if (!await b.waitKey('add_friend_id_input', timeoutSecs: 1)) {
      await b.openAddFriendDialogViaL3();
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
    if (await b.waitKey('add_friend_id_input', timeoutSecs: 3)) {
      dialogReady = true;
      break;
    }
  }
  if (!dialogReady) {
    final hasNewEntryButton = await b.waitKey(
      'new_entry_menu_button',
      timeoutSecs: 1,
    );
    final hasContactAppBarMenu = await b.waitKey(
      'contact_app_bar_menu_button',
      timeoutSecs: 1,
    );
    final hasTrailingOverride = await b.waitKey(
      'contact_app_bar_trailing_override',
      timeoutSecs: 1,
    );
    final shotPath = '/tmp/add_friend_dialog_${b.name}.png';
    await b.shot(shotPath);
    throw DriveError(
      '[${b.name}] add-friend dialog did not open '
      '(newEntryButton=$hasNewEntryButton '
      'contactAppBarMenu=$hasContactAppBarMenu '
      'trailingOverride=$hasTrailingOverride '
      'shot=$shotPath)',
    );
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
    if (await areFriends(a, toxB)) {
      print(
        '[${a.name}] detail screen already transitioned to accepted state '
        'for ${userId.substring(0, 16)}...',
      );
      return;
    }
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

String _defaultFriendRequestWording(String scenario) =>
    'RUI-$scenario-${DateTime.now().microsecondsSinceEpoch}';

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
  try {
    await openFriendProfile(inst, otherTox);
    if (!await inst.tryTapKey('user_profile_delete_friend_button')) {
      await inst.tapText('Delete');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    return true;
  } on DriveError catch (e) {
    print(
      '[${inst.name}] WARN deleteFriendViaProfile falling back to L3 delete: '
      '${e.message}',
    );
    if (await inst.deleteFriendViaL3(otherTox)) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      return true;
    }
    rethrow;
  }
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
    await Future<void>.delayed(const Duration(seconds: 3));
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
      print(
        '[pair] FAIL: custom_message cleanup unexpectedly formed friendship',
      );
      return 1;
    }
  }
  // Leave the pair in a reusable no-friend shell so the next no-friend
  // scenario can continue the same launch without another recovery dance.
  await ensureContactsShell(a);
  await ensureNewEntryShell(b);
  // Let any late friend-application deletion callbacks from the just-refused
  // request settle before the next no-friend scenario re-sends to the same
  // peer. Without this pause we've seen the next request arrive in native
  // pending_applications_, then get cleared before l3_dump_state surfaces it.
  await Future<void>.delayed(const Duration(seconds: 4));
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

Future<Set<String>> _groupConversationCandidates(Inst inst) async {
  final state = await inst.dumpState();
  final candidates = <String>{};
  final known = (state['knownGroups'] as List?) ?? const <dynamic>[];
  for (final g in known) {
    final id = g?.toString().trim() ?? '';
    if (id.isNotEmpty) candidates.add(id);
  }
  final convs = (state['conversations'] as List?) ?? const <dynamic>[];
  for (final c in convs) {
    if (c is! Map) continue;
    if (c['type'] != 2) continue;
    var cid = c['conversationID']?.toString().trim() ?? '';
    if (cid.isEmpty) continue;
    if (cid.startsWith('group_')) cid = cid.substring('group_'.length);
    if (cid.isNotEmpty) candidates.add(cid);
  }
  return candidates;
}

/// Whether the chat surface is on an OPEN group conversation. When
/// [requireGroupId] is given, the OPEN conversation must be exactly that group
/// (`group_<id>`) — not merely "some group". This matters across retries
/// (codex): `_leaveAllGroups` quits a group but does NOT clear the active
/// selection (the quit path leaves `activePeerId` set), so a stale `group_<old>`
/// detail would otherwise satisfy an any-group check and the next send would
/// target the wrong / already-left group.
Future<bool> _chatSurfaceReadyForAnyGroup(
  Inst inst, {
  int timeoutSecs = 10,
  String? requireGroupId,
}) async {
  final wantConv = requireGroupId == null ? null : 'group_$requireGroupId';
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final shellTab = await _homeShellTab(inst);
    final currentConversation = await _currentConversationId(inst);
    final hasInput = await inst.waitKey(
      'chat_input_text_field',
      timeoutSecs: 1,
    );
    final convOk = wantConv == null
        ? (currentConversation?.startsWith('group_') ?? false)
        : currentConversation == wantConv;
    if (shellTab == 'chats' && convOk && hasInput) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<void> openGroupChat(
  Inst inst, {
  required String groupId,
  required String groupName,
}) async {
  await inst.foreground();
  // Require THIS group to be the open one — an early-return on "any group open"
  // would wrongly short-circuit when a stale (e.g. just-left) group detail is
  // still showing after a retry (codex).
  if (await _chatSurfaceReadyForAnyGroup(
    inst,
    timeoutSecs: 2,
    requireGroupId: groupId,
  )) {
    return;
  }
  await returnToChatsHome(inst, rounds: 4);
  final conversationKey = 'conversation_list_item:group_$groupId';
  if (!await inst.tryTapKey(conversationKey, retries: 2) &&
      !await inst.tryTapKey('group_list_tile:$groupId', retries: 2)) {
    if (!await _tryTapText(inst, groupName)) {
      throw DriveError(
        '[${inst.name}] failed to open group chat '
        '(groupId=${_shortId(groupId)} name="$groupName")',
      );
    }
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  if (!await _chatSurfaceReadyForAnyGroup(
    inst,
    timeoutSecs: 8,
    requireGroupId: groupId,
  )) {
    throw DriveError(
      '[${inst.name}] group chat did not become ready '
      '(groupId=${_shortId(groupId)} name="$groupName" '
      'currentConversation=${await _currentConversationId(inst)})',
    );
  }
}

class _CreatedGroup {
  _CreatedGroup({required this.groupId, required this.chatId});
  final String groupId;
  final String chatId;
}

Future<_CreatedGroup> _createGroup(
  Inst inst,
  String name, {
  bool private = false,
}) async {
  final res = await inst.l3('l3_create_group', {
    'name': name,
    if (private) 'type': 'private',
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_create_group is test-gated. Drive the REAL
    // AddGroupDialog instead — the genuinely valuable real-UI create path.
    return _createGroupViaUI(inst, name, groupType: private ? 'private' : 'public');
  }
  if (res['ok'] != true) {
    throw DriveError('[${inst.name}] l3_create_group failed: $res');
  }
  final groupId = (res['groupId']?.toString() ?? '').trim();
  final chatId = (res['chatId']?.toString() ?? '').trim();
  if (groupId.isEmpty) {
    throw DriveError('[${inst.name}] l3_create_group returned empty groupId');
  }
  if (chatId.length != 64) {
    throw DriveError(
      '[${inst.name}] l3_create_group returned invalid chatId '
      '(groupId=${_shortId(groupId)} chatId="$chatId")',
    );
  }
  return _CreatedGroup(groupId: groupId, chatId: chatId);
}

/// Invite [userId] (a friend's Tox id) to [groupId] over the friend connection.
Future<void> _inviteToGroup(Inst inst, String groupId, String userId) async {
  final res = await inst.l3('l3_invite_to_group', {
    'groupId': groupId,
    'userId': userId,
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_invite_to_group is test-gated. Drive the
    // REAL group add-member screen instead.
    await _inviteToGroupViaUI(inst, groupId, userId);
    return;
  }
  if (res['ok'] != true) {
    throw DriveError('[${inst.name}] l3_invite_to_group failed: $res');
  }
}

/// Real-UI create-group for fresh/non-test accounts where `l3_create_group` is
/// test-gated. Drives the REAL AddGroupDialog (opened via the ungated
/// `l3_open_add_group_dialog` hook → pick Private → type name → Create) and
/// resolves A's own new group by its unique [name]. The 64-char NGC chat-id is
/// not surfaced through the UI path — runGroupMessage's PRIVATE flow never uses
/// it (peers connect over the friend link, not a chat-id DHT join) — so chatId
/// comes back empty.
Future<_CreatedGroup> _createGroupViaUI(
  Inst inst,
  String name, {
  String groupType = 'private',
}) async {
  await inst.foreground();
  final before = await _groupConversationCandidates(inst);
  final opened = await inst.l3('l3_open_add_group_dialog');
  if (opened['ok'] != true) {
    throw DriveError(
      '[${inst.name}] l3_open_add_group_dialog failed: $opened',
    );
  }
  if (!await inst.waitKey('add_group_create_name_input', timeoutSecs: 12)) {
    await inst.shot('/tmp/ui_group_create_noinput_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI create: AddGroupDialog name input never appeared',
    );
  }
  // Select the group-type segment. Keys live on KeyedSubtree label wrappers so
  // the tap is a single, locale-independent selection (selection is idempotent;
  // tapping Public too makes the choice deterministic rather than relying on the
  // default). Private = invite-only NGC (reliable same-host); conference =
  // legacy Tox conference (tox_conference_new).
  final segmentKey = switch (groupType) {
    'public' => 'add_group_type_public_segment',
    'conference' => 'add_group_type_conference_segment',
    _ => 'add_group_type_private_segment',
  };
  await inst.tapKey(segmentKey);
  await Future<void>.delayed(const Duration(milliseconds: 200));
  await inst.focusType('add_group_create_name_input', name);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('add_group_create_submit_button');
  // On success the dialog pops and A's own group surfaces as a fresh type==2
  // conversation titled [name]; resolve it unambiguously by that unique name.
  final gid = await _waitForJoinedGroup(
    inst,
    name,
    before: before,
    timeoutSecs: 30,
  );
  if (gid == null) {
    await inst.shot('/tmp/ui_group_create_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI create: new group "$name" did not appear '
      'after Create',
    );
  }
  return _CreatedGroup(groupId: gid, chatId: '');
}

/// Real-UI invite for fresh/non-test accounts where `l3_invite_to_group` is
/// test-gated. Deep-links to the REAL group add-member screen (ungated
/// `l3_open_group_add_member`), selects the friend via the real contact item,
/// and taps the real confirm button (`inviteUserToGroup`). [friendTox] is the
/// friend's Tox id; the add-member contact-item key is keyed by the friend's
/// stored userID, so resolve it from [inst]'s own contact list by pubkey (the
/// SAME list/format the key derives from) to avoid tox-id-vs-pubkey / casing
/// mismatches in the key suffix.
Future<void> _inviteToGroupViaUI(
  Inst inst,
  String groupId,
  String friendTox,
) async {
  final s = await inst.dumpState();
  String? friendUserId;
  for (final f in (s['friends'] as List?) ?? const []) {
    if (f is Map &&
        _pubkey(f['userId']?.toString() ?? '') == _pubkey(friendTox)) {
      friendUserId = f['userId']?.toString();
      break;
    }
  }
  if (friendUserId == null || friendUserId.isEmpty) {
    throw DriveError(
      '[${inst.name}] real-UI invite: friend ${_shortId(friendTox)} '
      'not in contact list',
    );
  }
  await inst.foreground();
  final opened = await inst.l3('l3_open_group_add_member', {
    'groupId': groupId,
  });
  if (opened['ok'] != true) {
    throw DriveError(
      '[${inst.name}] l3_open_group_add_member failed: $opened',
    );
  }
  final itemKey = 'add_member_contact_item:$friendUserId';
  if (!await inst.waitKey(itemKey, timeoutSecs: 12)) {
    await inst.shot('/tmp/ui_group_addmember_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] real-UI invite: contact not selectable ($itemKey)',
    );
  }
  // KeyedSubtree-wrapped item → single-fire select (the toggle would net-empty
  // under flutter_skill's double tap otherwise). Confirm is likewise wrapped so
  // its invite+pop fires once.
  await inst.tapKey(itemKey);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('group_member_invite_confirm_button');
}

/// Enable native auto-accept of group invites on [inst] so an inbound PRIVATE
/// group invite is accepted over the friend link via `tox_group_invite_accept`
/// (the correct private-group join). Without this, a manual join-by-chat-id does
/// a public DHT join and lands the peer in a DISCONNECTED public group.
Future<void> _setAutoAcceptGroupInvites(Inst inst, bool value) async {
  var res = await inst.l3('l3_set_setting', {
    'key': 'autoAcceptGroupInvites',
    'value': '$value',
  });
  if (res['error'] == 'non_test_account') {
    // Fresh / non-test account: l3_set_setting is test-gated. Use the ungated
    // campaign hook (same Prefs + native ffi sync). Without this the whole
    // "B auto-joins" flow can't even start (codex CRITICAL).
    res = await inst.l3('l3_set_auto_accept_group_invites', {'value': '$value'});
  }
  // Hard gate (codex): this is the precondition that lets B accept the PRIVATE
  // invite over the friend link instead of a wrong public DHT join. If it didn't
  // stick, fail loudly rather than silently fall through to a misjoin.
  if (res['ok'] != true) {
    throw DriveError(
      '[${inst.name}] set autoAcceptGroupInvites=$value failed: $res',
    );
  }
}

Future<bool> _getAutoAcceptGroupInvites(Inst inst) async {
  final s = await inst.dumpState();
  return s['autoAcceptGroupInvites'] == true;
}

/// Poll until [inst]'s LIVE autoAcceptGroupInvites matches [expected]. The
/// l3_set_setting write must propagate to the cached/native flag before an
/// inbound invite can be auto-accepted; only checking the setter's ok is the
/// weaker precondition (codex). Mirrors the existing private-group drivers.
Future<bool> _waitAutoAcceptGroupInvites(
  Inst inst,
  bool expected, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _getAutoAcceptGroupInvites(inst) == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Resolve B's auto-joined group for THIS attempt. B's auto-joined PRIVATE group
/// does not reliably surface in Dart-side `knownGroups` (that only tracks
/// SELF-created groups), so look at its type==2 CONVERSATIONS. Binds
/// UNAMBIGUOUSLY across retries (codex): prefer the conversation whose showName
/// is the attempt's UNIQUE [name]; before the name has synced, fall back to the
/// single fresh candidate vs [before] (knownGroups ∪ conversation gids) — if more
/// than one fresh candidate exists (e.g. a prior failed attempt's group surfaced
/// during this wait) it keeps polling rather than guessing. Returns null on
/// timeout.
Future<String?> _waitForJoinedGroup(
  Inst inst,
  String name, {
  required Set<String> before,
  int timeoutSecs = 45,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final state = await inst.dumpState();
    // 1. Exact name match (unambiguous — each retry uses a distinct name).
    for (final c in (state['conversations'] as List?) ?? const []) {
      if (c is! Map || c['type'] != 2) continue;
      if ((c['showName']?.toString() ?? '') != name) continue;
      var cid = c['conversationID']?.toString().trim() ?? '';
      if (cid.startsWith('group_')) cid = cid.substring('group_'.length);
      if (cid.isNotEmpty) return cid;
    }
    // 2. Fallback while the name hasn't synced: exactly ONE fresh candidate.
    final fresh = (await _groupConversationCandidates(inst)).difference(before);
    if (fresh.length == 1) return fresh.first;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return null;
}

/// Leave every group [inst] currently has (best-effort). Used to clean up a
/// failed retry attempt so the next one starts with NO group candidates, which
/// keeps the single-fresh resolution unambiguous.
Future<void> _leaveAllGroups(Inst inst) async {
  for (final gid in await _groupConversationCandidates(inst)) {
    try {
      final r = await inst.l3('l3_leave_group', {'groupId': gid});
      if (r['error'] == 'non_test_account') {
        // Fresh / non-test account: l3_leave_group is test-gated. Use the
        // ungated cleanup hook so a failed attempt's group doesn't leak into
        // the next retry (codex IMPORTANT — keeps single-fresh resolution sound).
        await inst.l3('l3_leave_group_unchecked', {'groupId': gid});
      }
    } on DriveError {
      // best effort
    }
  }
}

/// Wait until [inst] has no group conversation candidates left (after leaving).
Future<void> _waitGroupCandidatesDrained(
  Inst inst, {
  int timeoutSecs = 15,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if ((await _groupConversationCandidates(inst)).isEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
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

Future<String> _lastMessageForConversation(
  Inst inst,
  String conversationId,
) async {
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List? ?? const [])) {
    if (c is! Map) continue;
    if (c['conversationID']?.toString() != conversationId) continue;
    return c['lastMessageText']?.toString() ?? '';
  }
  return '';
}

Future<bool> _waitGroupMessageAnyConversation(
  Inst inst,
  String text, {
  int timeoutSecs = 60,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    await inst.foreground();
    final candidates = await _groupConversationCandidates(inst);
    for (final candidate in candidates) {
      final state = await inst.dumpState(conversationId: 'group_$candidate');
      final messages = (state['messages'] as List?) ?? const <dynamic>[];
      for (final m in messages) {
        if (m is Map && m['text']?.toString() == text) {
          return true;
        }
      }
      if (await _lastMessageForConversation(inst, 'group_$candidate') == text) {
        return true;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  final candidates = await _groupConversationCandidates(inst);
  print(
    '[${inst.name}] WARN group text "$text" not found across candidates='
    '$candidates',
  );
  for (final candidate in candidates) {
    final state = await inst.dumpState(conversationId: 'group_$candidate');
    final messages = (state['messages'] as List?) ?? const <dynamic>[];
    final summary = <Map<String, Object?>>[
      for (final m in messages)
        if (m is Map)
          {'msgID': m['msgID'], 'isSelf': m['isSelf'], 'text': m['text']},
    ];
    print(
      '[${inst.name}] candidate group_$candidate '
      'last="${await _lastMessageForConversation(inst, 'group_$candidate')}" '
      'messages=$summary',
    );
  }
  return false;
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

Future<int> _groupMemberCount(Inst inst, String groupId) async {
  try {
    final r = await inst.l3('l3_group_member_list', {'groupId': groupId});
    if (r['error'] == 'non_test_account') {
      // Fresh / non-test account: the full member-list tool is test-gated. Use
      // the ungated count hook so the peer-readiness gate can pass (codex
      // CRITICAL — otherwise the gate always sees 0 and never connects).
      final r2 = await inst.l3('l3_group_member_count', {'groupId': groupId});
      if (r2['ok'] != true) return 0;
      return (r2['count'] as num?)?.toInt() ?? 0;
    }
    if (r['ok'] != true) return 0;
    final members = (r['members'] as List?) ?? const [];
    return members.length;
  } on DriveError {
    return 0;
  }
}

/// NGC peer discovery on same-host is a timing race: after the joiner joins the
/// group, the creator and joiner must find each OTHER as group peers via the DHT
/// before any group message can deliver. A fixed post-join delay races this — the
/// send then fires with 0 peers and nothing is delivered (the "joiner shows an
/// empty group / creator keeps only its self-send" flake). Gate the send on the
/// real precondition: poll the group member list on BOTH sides until each sees
/// the other (>= 2 members = self + the peer).
Future<bool> _waitGroupPeersConnected(
  Inst a,
  String groupIdA,
  Inst b,
  String groupIdB, {
  int timeoutSecs = 90,
}) async {
  final sw = Stopwatch()..start();
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  var aCount = 0;
  var bCount = 0;
  while (DateTime.now().isBefore(deadline)) {
    aCount = await _groupMemberCount(a, groupIdA);
    bCount = await _groupMemberCount(b, groupIdB);
    if (aCount >= 2 && bCount >= 2) {
      print(
        '[pair] group peers connected after ${sw.elapsedMilliseconds}ms '
        '(A members=$aCount B members=$bCount)',
      );
      return true;
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  print(
    '[pair] WARN group peers NOT connected within ${timeoutSecs}s '
    '(A members=$aCount B members=$bCount)',
  );
  return false;
}

// Bidirectional message delivery through a real-UI group. Defaults drive a
// PRIVATE NGC group (the validated `group_message` path); pass
// groupType:'conference' (+ distinct label/prefixes) to drive a legacy Tox
// CONFERENCE instead — same flow (create via the real dialog, A invites, B
// auto-joins, both send through the real composer) because the C++
// InviteUserToGroup branches NGC vs conference (tox_group_invite_friend vs
// tox_conference_invite) and auto-accept covers both.
Future<int> runGroupMessage(
  Inst a,
  Inst b,
  String nickA,
  String nickB, {
  String groupType = 'private',
  String label = 'GROUP',
  String namePrefix = 'RUI-GROUP',
  String msgPrefix = 'RUIGROUP',
}) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final friendsReady = await _retryBool(
    () async => await areFriends(a, toxB) && await areFriends(b, toxA),
    label: '$label friendship ready',
    attempts: 20,
    intervalMs: 1000,
  );
  if (!friendsReady) {
    print('[pair] $label requires an existing friendship');
    return 1;
  }

  await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
  await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  await a.waitExt('ext.mcp.toolkit.l3_create_group');
  await a.waitExt('ext.mcp.toolkit.l3_join_group');
  await a.waitExt('ext.mcp.toolkit.l3_send_group_text');
  await b.waitExt('ext.mcp.toolkit.l3_join_group');
  await b.waitExt('ext.mcp.toolkit.l3_send_group_text');
  for (final ext in fixtureCBootstrapExtensions) {
    await a.waitExt(ext);
    await b.waitExt(ext);
  }
  await wireFullMeshBootstrap([
    BootstrapTarget('A', a.vm, a.iso),
    BootstrapTarget('B', b.vm, b.iso),
  ]);

  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  // PRIVATE group: peers connect over the existing FRIEND connection (reliable
  // same-host) instead of the flaky public-NGC DHT announce/search that made
  // group delivery a coin-flip (founder's HandleGroupPeerJoin never fired on
  // ~half of same-host runs). B must ACCEPT the invite over the friend link
  // (native tox_group_invite_accept) — a manual join-by-chat-id instead does a
  // public DHT join and lands B in a DISCONNECTED public group (privacy_state
  // mismatch, 0 peers). Enable auto-accept on B, then A invites; B auto-joins.
  //
  // The NGC peer connection between two SEPARATE same-host processes is still
  // probabilistic (the in-process tim2tox auto_tests never hit this), so retry
  // the whole setup with a FRESH private group when the peers don't connect.
  // Confirm B's auto-accept is LIVE before inviting (codex: the setter's `ok` is
  // the weaker precondition; the flag must actually be set for the invite to be
  // accepted over the friend link). Capture the prior value to RESTORE it after,
  // so this scenario doesn't leak mutated account state into later reused runs.
  final bPriorAutoAccept = await _getAutoAcceptGroupInvites(b);
  await _setAutoAcceptGroupInvites(b, true);
  if (!await _waitAutoAcceptGroupInvites(b, true, timeoutSecs: 10)) {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
    print('[pair] FAIL: B autoAcceptGroupInvites did not take effect');
    return 1;
  }
  try {
    var groupName = '$namePrefix-$nonce';
    var groupIdA = '';
    var groupIdB = '';
    var groupReady = false;
    for (var attempt = 1; attempt <= 3 && !groupReady; attempt++) {
      if (attempt > 1) {
        // Clean up the prior attempt's group on BOTH sides so each retry starts
        // with NO group candidates — this makes the single-fresh resolution
        // unambiguous even if a prior attempt's group surfaces late (codex). The
        // peer-gate below is the final guard: a mispaired/stale groupIdB can't
        // pass it (a left/failed group has < 2 connected members).
        await _leaveAllGroups(b);
        await _leaveAllGroups(a);
        await _waitGroupCandidatesDrained(b);
        await _waitGroupCandidatesDrained(a);
        groupIdA = '';
        groupIdB = '';
      }
      groupName = '$namePrefix-$nonce-$attempt';
      // After cleanup this is empty on a retry; on attempt 1 it captures any
      // pre-existing groups so only THIS attempt's auto-join is fresh.
      final before = await _groupConversationCandidates(b);
      // Conference has no l3 create path (l3_create_group only does public/
      // private NGC), so drive the real dialog directly; NGC types still try the
      // l3 tool first and fall back to the dialog on non-test accounts.
      final created = groupType == 'conference'
          ? await _createGroupViaUI(a, groupName, groupType: 'conference')
          : await _createGroup(a, groupName, private: groupType == 'private');
      groupIdA = created.groupId;
      await _inviteToGroup(a, groupIdA, toxB);
      // Resolve B's auto-joined group UNAMBIGUOUSLY by this attempt's unique
      // name (conversation-based — B's auto-joined private group may not surface
      // in knownGroups), with a single-fresh-candidate fallback.
      final gidB = await _waitForJoinedGroup(
        b,
        groupName,
        before: before,
        timeoutSecs: 45,
      );
      if (gidB == null) {
        print(
          '[pair] group attempt $attempt/3: B did not auto-join a new group; '
          'retrying with a fresh group',
        );
        continue;
      }
      groupIdB = gidB;
      // Gate on real NGC peer connection (not a fixed delay).
      if (await _waitGroupPeersConnected(
        a,
        groupIdA,
        b,
        groupIdB,
        timeoutSecs: 45,
      )) {
        groupReady = true;
      } else {
        print(
          '[pair] group attempt $attempt/3: peers did not connect; '
          'retrying with a fresh group',
        );
      }
    }
    final tag = label.toLowerCase();
    if (!groupReady) {
      await a.shot('/tmp/ui_${tag}_message_nopeers_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_${tag}_message_nopeers_B.png');
      print(
        '[pair] FAIL: $label peers did not connect after 3 attempts '
        '(same-host cross-process discovery) '
        '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
      );
      return 1;
    }
    await openGroupChat(b, groupId: groupIdB, groupName: groupName);

    final m1 = '$msgPrefix-AtoB-$nonce';
    await openGroupChat(a, groupId: groupIdA, groupName: groupName);
    final aSent = await sendComposerMessage(a, m1);
    final bGot = await _waitGroupMessageAnyConversation(b, m1, timeoutSecs: 60);
    print(
      '[pair] $label A->B sent=$aSent received=$bGot '
      '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
    );

    final m2 = '$msgPrefix-BtoA-$nonce';
    await openGroupChat(a, groupId: groupIdA, groupName: groupName);
    await openGroupChat(b, groupId: groupIdB, groupName: groupName);
    final bSent = await sendComposerMessage(b, m2);
    final aGot = await _waitGroupMessageAnyConversation(a, m2, timeoutSecs: 60);
    print(
      '[pair] $label B->A sent=$bSent received=$aGot '
      '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
    );

    await a.shot('/tmp/ui_${tag}_message_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_${tag}_message_B.png');

    if (aSent && bGot && bSent && aGot) {
      print('[pair] PASS: bidirectional real-UI $label message delivery');
      return 0;
    }
    print(
      '[pair] FAIL: $label A->B(sent=$aSent,recv=$bGot) '
      'B->A(sent=$bSent,recv=$aGot)',
    );
    return 1;
  } finally {
    // Restore B's auto-accept so it doesn't leak into later reused scenarios.
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// Single-instance real-UI group-create gate (S126/S127/S128/S129/S130): A opens
/// the REAL add-group dialog, creates a [groupType] group, opens the new group
/// conversation, and sends one message through the real composer — asserting the
/// own-sent bubble renders. No second peer / networking, so it is a fast,
/// deterministic surface check (dialog → create → open → composer send),
/// distinct from the two-process delivery gate (`group_message`). Only `a` is
/// driven; `b` is launched-but-idle.
Future<int> runGroupCreate(
  Inst inst,
  String nick, {
  String groupType = 'private',
}) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-GC-$nonce';
  final created = await _createGroupViaUI(inst, name, groupType: groupType);
  final gid = created.groupId;
  await openGroupChat(inst, groupId: gid, groupName: name);
  final msg = 'RUIGC-$nonce';
  final sent = await sendComposerMessage(inst, msg);
  // The own-sent message lands in the local group history regardless of peers,
  // so this asserts the composer→render surface without needing a joiner.
  final rendered = await _waitGroupMessageAnyConversation(
    inst,
    msg,
    timeoutSecs: 30,
  );
  await inst.shot('/tmp/ui_group_create_${inst.name}.png');
  if (sent && rendered) {
    print(
      '[pair] PASS: real-UI group create+open+composer-send '
      '(gid=${_shortId(gid)} type=$groupType)',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group create flow (sent=$sent rendered=$rendered '
    'gid=${_shortId(gid)} type=$groupType)',
  );
  return 1;
}

// ===========================================================================
// Single-instance LOGIN + SETTINGS real-UI scenarios.
//
// These drive the REAL login/settings widgets a user actually touches on ONE
// live instance (B stays launched-but-idle, exactly like group_create). They
// reuse `ensureHome` (the real "Register new account" click-through) for the
// logged-in precondition, then tap the real settings controls and assert the
// real side-effect via `l3_dump_state` (autoLogin / notificationSound /
// sessionReady / currentAccountToxId) or the real UI response (snackbar /
// dialog mount / login-page transition). New keys driven here
// (settings_set_password_* , login_page_account_card:<tox>) require a rebuilt
// app bundle.
// ===========================================================================

/// Open the Settings tab and wait for a settings landmark. Robust against a
/// transient post-dialog re-render or a backgrounded window: re-foreground and
/// re-tap the sidebar tab a few rounds before giving up.
Future<void> _openSettings(Inst inst) async {
  for (var round = 0; round < 5; round++) {
    await inst.foreground();
    if (await inst.waitKey('settings_copy_tox_id_button', timeoutSecs: 2)) {
      return;
    }
    await inst.tryTapKey('sidebar_settings_tab');
    if (await inst.waitKey('settings_copy_tox_id_button', timeoutSecs: 5)) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 800));
  }
  await inst.shot('/tmp/ui_settings_noopen_${inst.name}.png');
  throw DriveError('[${inst.name}] settings did not open from sidebar tab');
}

/// Poll l3_dump_state until a top-level bool field equals [want] (no throw).
Future<bool> _waitBoolState(
  Inst inst,
  String field,
  bool want, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if ((await inst.dumpState())[field] == want) return true;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  return false;
}

/// S100 — copy Tox ID from settings: real tap on the keyed copy button surfaces
/// the "ID copied to clipboard" snackbar.
Future<bool> _settingsCopyId(Inst inst) async {
  await _openSettings(inst);
  await inst.tapKey('settings_copy_tox_id_button');
  final ok = await inst.waitText('ID copied to clipboard', timeoutSecs: 8);
  print('[pair] settings_copy_id: snackbar=$ok');
  return ok;
}

/// Auto-login switch: real tap flips `autoLogin` in l3_dump_state; tap back
/// restores it (proves the switch drives the real Prefs-backed setting).
Future<bool> _settingsAutoLogin(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['autoLogin'] == true;
  await inst.tapKey('settings_auto_login_switch');
  final flipped = await _waitBoolState(inst, 'autoLogin', !before);
  await inst.tapKey('settings_auto_login_switch');
  final restored = await _waitBoolState(inst, 'autoLogin', before);
  print(
    '[pair] settings_autologin: before=$before flipped=$flipped '
    'restored=$restored',
  );
  return flipped && restored;
}

/// Notification-sound switch: real tap flips `notificationSound` in dump_state.
/// The switch lives in the lower GlobalSettingsSection, so it can be below the
/// fold — best-effort (a false here is reported, not a hard sweep failure).
Future<bool> _settingsNotification(Inst inst) async {
  await _openSettings(inst);
  final before = (await inst.dumpState())['notificationSound'] == true;
  if (!await inst.tryTapKey('settings_notification_sound_switch')) {
    print('[pair] settings_notification: switch not tappable (below fold?)');
    return false;
  }
  final flipped = await _waitBoolState(inst, 'notificationSound', !before);
  // Only restore if the first tap actually flipped it, so a passing result never
  // leaves notificationSound mutated.
  if (flipped) {
    await inst.tryTapKey('settings_notification_sound_switch');
    await _waitBoolState(inst, 'notificationSound', before);
  }
  print('[pair] settings_notification: before=$before flipped=$flipped');
  return flipped;
}

/// S105 — export chooser: real tap on Export Account mounts the chooser dialog
/// with both the .tox and full-backup options. ESC dismisses it without firing
/// the native save panel.
Future<bool> _settingsExportChooser(Inst inst) async {
  await _openSettings(inst);
  await inst.tapKey('settings_export_account_button');
  final tox = await inst.waitKey(
    'settings_export_profile_tox_option',
    timeoutSecs: 8,
  );
  final zip = await inst.waitKey(
    'settings_export_full_backup_option',
    timeoutSecs: 4,
  );
  try {
    await inst.osaEscape();
  } on DriveError {
    // best effort
  }
  await Future<void>.delayed(const Duration(milliseconds: 600));
  print('[pair] settings_export_chooser: tox=$tox zip=$zip');
  return tox && zip;
}

/// Set/change-password dialog: real tap opens it (keyed new/confirm fields),
/// fill matching values, Save → the dialog closes on the success path (real
/// PBKDF2 runs on the live isolate).
Future<bool> _settingsPassword(Inst inst) async {
  await _openSettings(inst);
  // Below-fold opener: drive it with `tap` (its direct _tryInvokeCallback opens
  // the dialog even off-screen; a coordinate tapAt would miss). See the logout
  // flow above for the same rationale.
  await inst.tapKey('settings_set_password_button');
  if (!await inst.waitKey('settings_set_password_new_field', timeoutSecs: 8)) {
    print('[pair] settings_password: dialog did not open');
    return false;
  }
  final pw = 'RuiPw-${DateTime.now().millisecondsSinceEpoch ~/ 1000}';
  await inst.focusType('settings_set_password_new_field', pw);
  await inst.focusType('settings_set_password_confirm_field', pw);
  // SINGLE-FIRE the save button: it calls Navigator.pop(password) on success, so
  // flutter_skill's double-firing tap would pop the dialog AND HomePage (blanking
  // the app) and tear down the ScaffoldMessenger before the success snackbar.
  if (!await inst.tapKeyCenter('settings_set_password_save_button')) {
    print('[pair] settings_password: save button not tappable');
    return false;
  }
  // The dialog pops on matching input BEFORE the async
  // AccountService.setAccountPassword write completes — so "dialog closed" alone
  // is a false pass. Assert the REAL save via the success snackbar (only shown
  // when setAccountPassword returns ok; real PBKDF2 runs on the live isolate, so
  // allow time).
  final saved = await inst.waitText(
    'Password set successfully',
    timeoutSecs: 25,
  );
  // Also require the dialog to be fully GONE. Unlike logout (whose
  // pushAndRemoveUntil tears down any stray route), nothing here cleans up a
  // second dialog if the below-fold opener ever double-opened — the single-fire
  // save would pop only the top one, the snackbar would still fire, and the
  // residual dialog (same field key) would leave a dirty false-green. Asserting
  // the field is gone catches that and proves the save closed the dialog.
  final dialogClosed = await inst.waitKeyGone(
    'settings_set_password_new_field',
    timeoutSecs: 8,
  );
  print(
    '[pair] settings_password: passwordSavedSnackbar=$saved '
    'dialogClosed=$dialogClosed',
  );
  return saved && dialogClosed;
}

/// Logout + saved-account relogin: real tap Logout → confirm → the app returns
/// to the login page (sessionReady=false) showing this account's saved-account
/// card → tap the card to quick-login back to HomePage (sessionReady=true).
///
/// PRECONDITION: the current account has NO password — tapping the saved-account
/// card then quick-logs-in directly. On a password-protected account `_quickLogin`
/// shows a password prompt instead, which this driver cannot satisfy (it does not
/// know the password), so the relogin times out and the gate fails cleanly. Run
/// on a freshly-registered account (which `ensureHome` provides), and in
/// `runSettingsSweep` this runs BEFORE `settings_password` for exactly this reason.
Future<bool> _settingsLogoutRelogin(Inst inst) async {
  final toxId =
      (await inst.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxId.isEmpty) {
    print('[pair] logout_relogin: no current toxId');
    return false;
  }
  await _openSettings(inst);
  // The logout button sits low in the (scrollable) settings list — often below
  // the fold. flutter_skill's `tap` opens it anyway via its direct
  // `_tryInvokeCallback` (the synthetic pointer misses off-screen, so the
  // callback fires exactly once → one dialog). A coordinate `tapAt` would miss.
  await inst.tapKey('settings_logout_button');
  if (!await inst.waitKey('settings_logout_confirm_button', timeoutSecs: 8)) {
    print('[pair] logout_relogin: confirm dialog did not open');
    return false;
  }
  // SINGLE-FIRE the confirm: it is an on-screen dialog button, so flutter_skill's
  // `tap` fires it TWICE (synthetic pointer hit + direct onPressed) → pops the
  // dialog AND HomePage, and `_logout`'s trailing `if (!mounted) return` then
  // skips `pushAndRemoveUntil(LoginPage)`, leaving an empty Navigator (blank
  // screen). tapKeyCenter dispatches exactly one pointer tap. See tapKeyCenter.
  if (!await inst.tapKeyCenter('settings_logout_confirm_button')) {
    print('[pair] logout_relogin: confirm button not tappable');
    return false;
  }
  final cardKey = 'login_page_account_card:$toxId';
  // Logout pushes the login page; the async saved-account-list load only pumps
  // while the window is FOREGROUND (a backgrounded window stalls it → blank
  // screenshot + card never renders). Re-foreground each round until the card
  // appears.
  var loggedOut = false;
  var cardShows = false;
  for (var round = 0; round < 15 && !cardShows; round++) {
    await inst.foreground();
    loggedOut = (await inst.dumpState())['sessionReady'] != true;
    if (loggedOut) {
      cardShows = await inst.waitKey(cardKey, timeoutSecs: 2);
    }
    if (!cardShows) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
    }
  }
  print(
    '[pair] logout_relogin: loggedOut=$loggedOut cardShows=$cardShows '
    '(tox=${_shortId(toxId)})',
  );
  if (!loggedOut || !cardShows) {
    await inst.foreground();
    await inst.shot('/tmp/ui_logout_${inst.name}.png');
    try {
      final inter = await inst.skill('interactiveStructured', const {});
      final keys = RegExp('login_page_account_card:[A-Za-z0-9]+')
          .allMatches(inter.toString())
          .map((m) => m.group(0))
          .toSet();
      print('[pair] logout DIAG: card keys seen=$keys want=$cardKey');
    } catch (_) {}
    return false;
  }
  // Quick-login back via the saved-account card (this account has no password).
  await inst.tapKey(cardKey);
  await inst.foreground();
  final relogin = await _waitBoolState(
    inst,
    'sessionReady',
    true,
    timeoutSecs: 40,
  );
  print('[pair] logout_relogin: reloginSessionReady=$relogin');
  return relogin;
}

/// settings_sweep — run the whole login+settings real-UI click suite on ONE
/// launch (reuses startup; maximizes cases per batch). logout_relogin runs LAST
/// because it mutates the session; password runs before it (also mutating).
Future<int> runSettingsSweep(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
    timeoutSecs: 90,
  );
  // Order matters: the deterministic real-click gates first; logout_relogin
  // BEFORE password (relogin via the saved-account card assumes no password);
  // password LAST (it sets a password — harmless once nothing follows).
  final results = <String, bool>{};
  results['copy_id'] = await _settingsCopyId(inst);
  results['export_chooser'] = await _settingsExportChooser(inst);
  results['autologin'] = await _settingsAutoLogin(inst);
  results['notification'] = await _settingsNotification(inst);
  results['logout_relogin'] = await _settingsLogoutRelogin(inst);
  results['password'] = await _settingsPassword(inst);
  final passed = results.values.where((v) => v).length;
  final total = results.length;
  print('[pair] settings_sweep RESULTS: $results ($passed/$total passed)');
  await inst.shot('/tmp/ui_settings_sweep_${inst.name}.png');
  // autologin + notification are best-effort: flutter_skill's synthetic tap on a
  // Material Switch does not reliably trigger onChanged (a known harness gap, like
  // the documented enterText{key}-needs-editable limitation), and the
  // notification switch can sit below the fold (flutter_skill has no scroll). The
  // HARD gates are the deterministic real-click flows: copy_id, export_chooser,
  // logout_relogin, password.
  final hardOk = results.entries
      .where((e) => e.key != 'notification' && e.key != 'autologin')
      .every((e) => e.value);
  return hardOk ? 0 : 1;
}

/// Open the REAL group profile from the group chat header (the keyed avatar →
/// `navigateToGroupProfile`). Idempotent: returns immediately if the profile is
/// already showing (`group_profile_id_text`). The chat for the group must be
/// open first (so the header avatar resolves to a groupID).
Future<void> _openGroupProfile(Inst inst) async {
  await inst.foreground();
  const sigKeys = [
    'group_profile_members_entry',
    'group_profile_edit_name_button',
    'group_profile_id_text',
  ];
  Future<bool> anyKey() async {
    for (final k in sigKeys) {
      if (await inst.waitKey(k, timeoutSecs: 1)) return true;
    }
    return false;
  }

  if (await anyKey()) return;
  await inst.tapKey('message_header_profile_avatar');
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (DateTime.now().isBefore(deadline)) {
    if (await anyKey()) return;
    await Future<void>.delayed(const Duration(milliseconds: 400));
  }
  // Diagnostic: dump which keys flutter_skill's interactiveStructured + the raw
  // tree actually see, so a failure distinguishes "override not rendered" from
  // "route not flutter_skill-reachable" from "key not matchable".
  try {
    final inter = await inst.skill('interactiveStructured', const {});
    final si = inter.toString();
    final ik = RegExp(r'group_profile[a-z_]*|message_header_profile_avatar')
        .allMatches(si)
        .map((m) => m.group(0))
        .toSet();
    print(
      '[${inst.name}] DIAG interactiveStructured len=${si.length} '
      'profile-keys=$ik; raw sample: '
      '${si.substring(0, si.length < 400 ? si.length : 400)}',
    );
  } catch (e) {
    print('[${inst.name}] DIAG interactiveStructured failed: $e');
  }
  await inst.shot('/tmp/ui_group_profile_noopen_${inst.name}.png');
  throw DriveError(
    '[${inst.name}] group profile did not open from the chat header '
    '(none of $sigKeys present)',
  );
}

/// Poll [inst]'s conversation list until the group `group_<gid>` row's showName
/// equals [expected] (the rename-refreshes-row assertion).
Future<bool> _waitGroupShowName(
  Inst inst,
  String gid,
  String expected, {
  int timeoutSecs = 20,
}) async {
  final want = 'group_$gid';
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    for (final c in (s['conversations'] as List?) ?? const []) {
      if (c is! Map) continue;
      if ((c['conversationID']?.toString() ?? '') != want) continue;
      if ((c['showName']?.toString() ?? '') == expected) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// S136 — single-instance: create a group, open its chat, open the group profile
/// from the REAL chat-header avatar, and assert the profile surfaces (group id +
/// members entry) render.
Future<int> runGroupProfileOpen(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-GP-$nonce';
  final created = await _createGroupViaUI(inst, name, groupType: 'private');
  await openGroupChat(inst, groupId: created.groupId, groupName: name);
  await _openGroupProfile(inst);
  final hasId = await inst.waitKey('group_profile_id_text', timeoutSecs: 5);
  final hasMembers = await inst.waitKey(
    'group_profile_members_entry',
    timeoutSecs: 5,
  );
  await inst.shot('/tmp/ui_group_profile_${inst.name}.png');
  if (hasId && hasMembers) {
    print(
      '[pair] PASS: real-UI group profile open '
      '(id+members surfaces, gid=${_shortId(created.groupId)})',
    );
    return 0;
  }
  print('[pair] FAIL: group profile open (id=$hasId members=$hasMembers)');
  return 1;
}

/// S153 — single-instance: create a group, open the profile, edit the name
/// through the REAL edit-name dialog, and assert the conversation-list row
/// refreshes to the new name.
Future<int> runGroupRename(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-GRN-$nonce';
  final newName = 'RENAMED-$nonce';
  final created = await _createGroupViaUI(inst, name, groupType: 'private');
  await openGroupChat(inst, groupId: created.groupId, groupName: name);
  await _openGroupProfile(inst);
  await inst.tapKey('group_profile_edit_name_button');
  if (!await inst.waitKey('group_profile_edit_name_field', timeoutSecs: 10)) {
    await inst.shot('/tmp/ui_group_rename_nodialog_${inst.name}.png');
    throw DriveError('[${inst.name}] group edit-name dialog did not open');
  }
  await inst.focusType('group_profile_edit_name_field', newName);
  await Future<void>.delayed(const Duration(milliseconds: 300));
  await inst.tapKey('group_profile_edit_name_confirm_button');
  final refreshed = await _waitGroupShowName(
    inst,
    created.groupId,
    newName,
    timeoutSecs: 20,
  );
  await inst.shot('/tmp/ui_group_rename_${inst.name}.png');
  if (refreshed) {
    print(
      '[pair] PASS: real-UI group rename refreshes row '
      '("$name" → "$newName", gid=${_shortId(created.groupId)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group rename row did not refresh to "$newName" '
    '(gid=${_shortId(created.groupId)})',
  );
  return 1;
}

/// S135 — single-instance: create a group, then find + open it from the REAL
/// global search. CORRECTED (2026-06-08, codex): the old driver was wrong —
/// `message_search_field` is NOT on the chats home (the chats-home search field
/// is an unkeyed conversation-header TextField that shows an EMBEDDED
/// CustomSearch where the keyed field is suppressed); it only renders in the
/// desktop Cmd+Ctrl+F global-search overlay. And `search_result_message_<id>`
/// rows are MESSAGE-result tiles that push SearchChatHistoryWindow, not the
/// conversation — a no-message group has no such row. Corrected flow: open the
/// Cmd+Ctrl+F overlay (keyed `message_search_field`), type the group name, then
/// tap the KEYED result row — `search_result_group:<gid>` (or the
/// conversation-fallback `search_result_conversation:group_<gid>`), keys added
/// to custom_search.dart. Tapping by text was ambiguous with the query already
/// in the search field, so the rows are keyed. Desktop-only entry by construction.
Future<int> runGroupSearch(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final name = 'RUI-GSEARCH-$nonce';
  final created = await _createGroupViaUI(inst, name, groupType: 'private');
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  // Cmd+Ctrl+F opens the global-search overlay (the only surface that renders
  // the keyed message_search_field). key code 3 = 'f'.
  await inst._osa(
    'tell application "System Events" to key code 3 using '
    '{command down, control down}',
  );
  if (!await inst.waitKey('message_search_field', timeoutSecs: 10)) {
    await inst.shot('/tmp/ui_group_search_nofield_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] global search overlay (Cmd+Ctrl+F) did not open '
      '(message_search_field absent)',
    );
  }
  await inst.focusType('message_search_field', name);
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  // Tap the KEYED result row (NOT by text — tapping by name collides with the
  // query text in the search field). The group can surface either as a GROUPS
  // result (`search_result_group:<gid>`) or, if that FFI degrades, the
  // conversation-fallback row (`search_result_conversation:group_<gid>`).
  final groupRowKey = 'search_result_group:${created.groupId}';
  final convRowKey = 'search_result_conversation:group_${created.groupId}';
  String? rowKey;
  if (await inst.waitKey(groupRowKey, timeoutSecs: 8)) {
    rowKey = groupRowKey;
  } else if (await inst.waitKey(convRowKey, timeoutSecs: 4)) {
    rowKey = convRowKey;
  }
  if (rowKey == null) {
    await inst.shot('/tmp/ui_group_search_norow_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] group "$name" did not appear as a keyed search result '
      '($groupRowKey / $convRowKey, gid=${_shortId(created.groupId)})',
    );
  }
  await inst.tapKey(rowKey);
  final opened = await _chatSurfaceReadyForAnyGroup(
    inst,
    timeoutSecs: 10,
    requireGroupId: created.groupId,
  );
  await inst.shot('/tmp/ui_group_search_${inst.name}.png');
  if (opened) {
    print(
      '[pair] PASS: real-UI group search opens conversation '
      '(gid=${_shortId(created.groupId)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group search did not open the conversation '
    '(name="$name", gid=${_shortId(created.groupId)})',
  );
  return 1;
}

/// S144 — single-instance: create a group, then open the REAL add-member screen
/// via the ungated `l3_open_group_add_member` deep-link and assert it mounted
/// (the keyed `group_member_invite_confirm_button` is present regardless of
/// whether the contact list has entries). Surface check distinct from S145.
Future<int> runGroupAddMemberOpen(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GADD-$nonce',
    groupType: 'private',
  );
  await inst.foreground();
  final opened = await inst.l3('l3_open_group_add_member', {
    'groupId': created.groupId,
  });
  if (opened['ok'] != true) {
    await inst.shot('/tmp/ui_group_add_member_open_fail_${inst.name}.png');
    throw DriveError('[${inst.name}] l3_open_group_add_member failed: $opened');
  }
  final mounted = await inst.waitKey(
    'group_member_invite_confirm_button',
    timeoutSecs: 12,
  );
  await inst.shot('/tmp/ui_group_add_member_open_${inst.name}.png');
  if (mounted) {
    print(
      '[pair] PASS: real-UI add-member screen opened '
      '(confirm button present, gid=${_shortId(created.groupId)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: add-member screen did not mount '
    '(no confirm button, gid=${_shortId(created.groupId)})',
  );
  return 1;
}

/// S145 — two-process: A and B are friends; A creates a group, opens the REAL
/// add-member picker, selects B (keyed contact item), confirms, and B joins.
/// The standalone add-member-picker gate (S144 only opens the screen). Reuses
/// `_inviteToGroupViaUI`'s exact select+confirm path; B auto-accepts and is
/// restored in `finally`.
Future<int> runGroupAddMemberPicker(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final friendsReady = await _retryBool(
    () async => await areFriends(a, toxB) && await areFriends(b, toxA),
    label: 'group_add_member_picker friendship ready',
    attempts: 20,
    intervalMs: 1000,
  );
  if (!friendsReady) {
    print('[pair] group_add_member_picker requires an existing friendship');
    return 1;
  }
  await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
  await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  for (final ext in fixtureCBootstrapExtensions) {
    await a.waitExt(ext);
    await b.waitExt(ext);
  }
  await wireFullMeshBootstrap([
    BootstrapTarget('A', a.vm, a.iso),
    BootstrapTarget('B', b.vm, b.iso),
  ]);

  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final bPriorAutoAccept = await _getAutoAcceptGroupInvites(b);
  await _setAutoAcceptGroupInvites(b, true);
  if (!await _waitAutoAcceptGroupInvites(b, true, timeoutSecs: 10)) {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
    print('[pair] FAIL: B autoAcceptGroupInvites did not take effect');
    return 1;
  }
  try {
    final created = await _createGroupViaUI(
      a,
      'RUI-GPICK-$nonce',
      groupType: 'private',
    );
    await _inviteToGroupViaUI(a, created.groupId, toxB);
    var memberCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 60));
    while (DateTime.now().isBefore(deadline)) {
      memberCount = await _groupMemberCount(a, created.groupId);
      if (memberCount >= 2) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    await a.shot('/tmp/ui_group_add_member_picker_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_group_add_member_picker_B.png');
    if (memberCount >= 2) {
      print(
        '[pair] PASS: add-member picker invited B; A member count=$memberCount '
        '(gid=${_shortId(created.groupId)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: add-member picker — B never reached the group '
      '(A member count=$memberCount, gid=${_shortId(created.groupId)})',
    );
    return 1;
  } finally {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// Result of `_establishTwoProcessGroup`: both sides' group ids, the resolved
/// group name, and B's PRIOR autoAcceptGroupInvites value so the caller can
/// RESTORE it in a `finally` (the same leak-prevention `runGroupMessage` does).
class _EstablishedGroup {
  _EstablishedGroup({
    required this.groupIdA,
    required this.groupIdB,
    required this.groupName,
    required this.priorAutoAccept,
  });
  final String groupIdA;
  final String groupIdB;
  final String groupName;
  final bool priorAutoAccept;
}

/// Establish a live two-process group between A (creator) and B (auto-joiner),
/// replicating EVERYTHING `runGroupMessage` does UP TO the message send:
/// friendship gate, l3 group exts, full-mesh bootstrap, B auto-accept enable,
/// and the 3-attempt create+invite+join+peer-readiness loop. Returns an
/// `_EstablishedGroup` on success or `null` on failure (after logging +
/// screenshots). On a NON-null return, B's auto-accept is left ENABLED and the
/// caller MUST restore it in a `finally` via `result.priorAutoAccept`; on a
/// NULL return this helper attempts the restore itself. Nominal flow never
/// double-restores; the restores are best-effort (a failing l3 setter is
/// swallowed), so a residual auto-accept flag CAN leak — acceptable here because
/// these accounts are ephemeral (fresh per run) and `runGroupMessage` uses the
/// same best-effort pattern (codex). Additive clone of `runGroupMessage`'s setup
/// (the mild duplication protects the validated path).
Future<_EstablishedGroup?> _establishTwoProcessGroup(
  Inst a,
  Inst b,
  String nickA,
  String nickB, {
  String groupType = 'private',
  String namePrefix = 'RUI-GRP2',
}) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final friendsReady = await _retryBool(
    () async => await areFriends(a, toxB) && await areFriends(b, toxA),
    label: 'establishGroup friendship ready',
    attempts: 20,
    intervalMs: 1000,
  );
  if (!friendsReady) {
    print('[pair] establishGroup requires an existing friendship');
    return null;
  }

  await a.waitState((s) => s['isConnected'] == true, label: 'A connected');
  await b.waitState((s) => s['isConnected'] == true, label: 'B connected');
  await a.waitExt('ext.mcp.toolkit.l3_create_group');
  await a.waitExt('ext.mcp.toolkit.l3_join_group');
  await a.waitExt('ext.mcp.toolkit.l3_send_group_text');
  await b.waitExt('ext.mcp.toolkit.l3_join_group');
  await b.waitExt('ext.mcp.toolkit.l3_send_group_text');
  for (final ext in fixtureCBootstrapExtensions) {
    await a.waitExt(ext);
    await b.waitExt(ext);
  }
  await wireFullMeshBootstrap([
    BootstrapTarget('A', a.vm, a.iso),
    BootstrapTarget('B', b.vm, b.iso),
  ]);

  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final bPriorAutoAccept = await _getAutoAcceptGroupInvites(b);
  await _setAutoAcceptGroupInvites(b, true);
  if (!await _waitAutoAcceptGroupInvites(b, true, timeoutSecs: 10)) {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
    print('[pair] FAIL: B autoAcceptGroupInvites did not take effect');
    return null;
  }

  var groupName = '$namePrefix-$nonce';
  var groupIdA = '';
  var groupIdB = '';
  var groupReady = false;
  try {
    for (var attempt = 1; attempt <= 3 && !groupReady; attempt++) {
      if (attempt > 1) {
        await _leaveAllGroups(b);
        await _leaveAllGroups(a);
        await _waitGroupCandidatesDrained(b);
        await _waitGroupCandidatesDrained(a);
        groupIdA = '';
        groupIdB = '';
      }
      groupName = '$namePrefix-$nonce-$attempt';
      final before = await _groupConversationCandidates(b);
      final created = groupType == 'conference'
          ? await _createGroupViaUI(a, groupName, groupType: 'conference')
          : await _createGroup(a, groupName, private: groupType == 'private');
      groupIdA = created.groupId;
      await _inviteToGroup(a, groupIdA, toxB);
      final gidB = await _waitForJoinedGroup(
        b,
        groupName,
        before: before,
        timeoutSecs: 45,
      );
      if (gidB == null) {
        print(
          '[pair] establishGroup attempt $attempt/3: B did not auto-join a new '
          'group; retrying with a fresh group',
        );
        continue;
      }
      groupIdB = gidB;
      if (await _waitGroupPeersConnected(
        a,
        groupIdA,
        b,
        groupIdB,
        timeoutSecs: 45,
      )) {
        groupReady = true;
      } else {
        print(
          '[pair] establishGroup attempt $attempt/3: peers did not connect; '
          'retrying with a fresh group',
        );
      }
    }

    if (!groupReady) {
      await a.shot('/tmp/ui_establish_group_nopeers_A.png');
      await b.foreground();
      await b.shot('/tmp/ui_establish_group_nopeers_B.png');
      print(
        '[pair] FAIL: establishGroup peers did not connect after 3 attempts '
        '(same-host cross-process discovery) '
        '(groupIdA=${_shortId(groupIdA)} groupIdB=${_shortId(groupIdB)})',
      );
      if (!bPriorAutoAccept) {
        try {
          await _setAutoAcceptGroupInvites(b, false);
        } on DriveError catch (_) {}
      }
      return null;
    }

    return _EstablishedGroup(
      groupIdA: groupIdA,
      groupIdB: groupIdB,
      groupName: groupName,
      priorAutoAccept: bPriorAutoAccept,
    );
  } catch (_) {
    if (!bPriorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
    rethrow;
  }
}

/// S152 — two-process group: alternate 3 messages EACH way through the REAL
/// group composer (the group analogue of `runMessageBurst`).
Future<int> runGroupBurst(Inst a, Inst b, String nickA, String nickB) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GBURST',
  );
  if (est == null) {
    print('[pair] FAIL: group_burst could not establish a two-process group');
    return 1;
  }
  try {
    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    for (var i = 1; i <= 3; i++) {
      final mAtoB = 'RUIGBURST-A$i-$nonce';
      await openGroupChat(a, groupId: est.groupIdA, groupName: est.groupName);
      final aSent = await sendComposerMessage(a, mAtoB);
      final bGot = await _waitGroupMessageAnyConversation(
        b,
        mAtoB,
        timeoutSecs: 60,
      );
      if (!aSent || !bGot) {
        await a.shot('/tmp/ui_group_burst_fail_A.png');
        await b.foreground();
        await b.shot('/tmp/ui_group_burst_fail_B.png');
        print(
          '[pair] FAIL: group_burst A->$i sent=$aSent recv=$bGot '
          '(groupIdA=${_shortId(est.groupIdA)} '
          'groupIdB=${_shortId(est.groupIdB)})',
        );
        return 1;
      }

      final mBtoA = 'RUIGBURST-B$i-$nonce';
      await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
      final bSent = await sendComposerMessage(b, mBtoA);
      final aGot = await _waitGroupMessageAnyConversation(
        a,
        mBtoA,
        timeoutSecs: 60,
      );
      if (!bSent || !aGot) {
        await a.shot('/tmp/ui_group_burst_fail_A.png');
        await b.foreground();
        await b.shot('/tmp/ui_group_burst_fail_B.png');
        print(
          '[pair] FAIL: group_burst B->$i sent=$bSent recv=$aGot '
          '(groupIdA=${_shortId(est.groupIdA)} '
          'groupIdB=${_shortId(est.groupIdB)})',
        );
        return 1;
      }
    }

    await a.shot('/tmp/ui_group_burst_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_group_burst_B.png');
    print(
      '[pair] PASS: alternating real-UI group burst converged both directions '
      '(groupIdA=${_shortId(est.groupIdA)} '
      'groupIdB=${_shortId(est.groupIdB)})',
    );
    return 0;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// S155 — two-process group: after B accepts A's invite, A's member list shows
/// both members. Establish a live private group, then assert A's authoritative
/// NGC member count (`l3_group_member_count`) is >=2 AND the real members UI
/// surface mounts (group chat → profile → keyed members entry).
Future<int> runGroupMemberList(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GMEM',
  );
  if (est == null) {
    print(
      '[pair] FAIL: group_member_list could not establish a two-process group',
    );
    return 1;
  }
  try {
    var memberCount = 0;
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    while (DateTime.now().isBefore(deadline)) {
      memberCount = await _groupMemberCount(a, est.groupIdA);
      if (memberCount >= 2) break;
      await Future<void>.delayed(const Duration(seconds: 1));
    }

    // Best-effort UI-surface exercise: open A's group chat + profile and note
    // whether the members entry mounts. The AUTHORITATIVE assertion is the
    // member count (l3_group_member_count) — the group-profile route's keyed
    // widgets are not always flutter_skill-reachable, so the members-entry
    // presence is informational only and does NOT gate PASS.
    var membersEntryShown = false;
    try {
      await openGroupChat(a, groupId: est.groupIdA, groupName: est.groupName);
      await _openGroupProfile(a);
      membersEntryShown = await a.waitKey(
        'group_profile_members_entry',
        timeoutSecs: 5,
      );
    } on DriveError catch (e) {
      print('[${a.name}] member-list UI-surface best-effort skipped: ${e.message}');
    }

    await a.shot('/tmp/ui_group_member_list_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_group_member_list_B.png');

    if (memberCount >= 2) {
      print(
        '[pair] PASS: real-UI group member list shows >=2 members '
        '(A memberCount=$memberCount, membersEntryShown=$membersEntryShown, '
        'groupIdA=${_shortId(est.groupIdA)} '
        'groupIdB=${_shortId(est.groupIdB)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: group_member_list (A memberCount=$memberCount '
      'groupIdA=${_shortId(est.groupIdA)} '
      'groupIdB=${_shortId(est.groupIdB)})',
    );
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// Read a single conversation map (`group_<gid>` / `c2c_<id>`) from dump_state's
/// conversation list, or null if not present yet.
Future<Map<String, dynamic>?> _conversationEntry(
  Inst inst,
  String conversationId,
) async {
  final s = await inst.dumpState();
  for (final c in (s['conversations'] as List?) ?? const []) {
    if (c is! Map) continue;
    if (c['conversationID']?.toString() != conversationId) continue;
    return c.cast<String, dynamic>();
  }
  return null;
}

/// Poll until the conversation `conversationId` has `isPinned == expected`.
Future<bool> _waitConversationPinned(
  Inst inst,
  String conversationId,
  bool expected, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final entry = await _conversationEntry(inst, conversationId);
    if (entry != null && (entry['isPinned'] == true) == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the conversation `conversationId`'s unreadCount (from the top-level
/// conversation list, the same source the badge renders) satisfies [test].
Future<bool> _waitConversationUnread(
  Inst inst,
  String conversationId,
  bool Function(int unread) test, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final entry = await _conversationEntry(inst, conversationId);
    if (entry != null) {
      final unread = (entry['unreadCount'] as num?)?.toInt() ?? 0;
      if (test(unread)) return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the group conversation's history `messageCount` (from
/// `l3_dump_state {conversationId}`, the path-independent `ffi.getHistory`
/// readout) satisfies [test].
Future<bool> _waitGroupHistoryCount(
  Inst inst,
  String conversationId,
  bool Function(int count) test, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final st = await inst.dumpState(conversationId: conversationId);
    final count = (st['messageCount'] as num?)?.toInt() ?? -1;
    if (test(count)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Poll until the conversation `conversationId` is ABSENT from the sidebar list.
Future<bool> _waitConversationGone(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 20,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    final ids = [
      for (final c in (s['conversations'] as List?) ?? const [])
        if (c is Map) c['conversationID']?.toString(),
    ];
    if (!ids.contains(conversationId)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

/// Open the conversation-row context menu for `group_<gid>` via the ungated
/// `l3_open_conversation_menu` deep-link (flutter_skill cannot right-click /
/// long-press). Lands on the chats home first so the conversation list is
/// mounted.
Future<void> _openConversationMenu(Inst inst, String gid) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final r = await inst.l3('l3_open_conversation_menu', {
    'conversationId': 'group_$gid',
  });
  if (r['ok'] != true) {
    await inst.shot('/tmp/ui_conv_menu_open_fail_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] l3_open_conversation_menu failed for group_$gid: $r',
    );
  }
}

/// Dismiss an open context menu by tapping the modal barrier (top-left corner).
Future<void> _dismissContextMenu(Inst inst) async {
  await inst.tapAt(8, 8);
  await Future<void>.delayed(const Duration(milliseconds: 500));
}

/// Dispatch a conversation-row context-menu action (`pin`/`mark_read`/`delete`)
/// DIRECTLY through the production handler (`l3_open_conversation_menu` with an
/// `action`), bypassing the PopupMenuItem tap. flutter_skill double-fires
/// InkWell-backed menu items, which turns the `pin` toggle into a net no-op —
/// the exact reason the menu-item-tap leg was unreliable. The deep-link runs the
/// same `_dispatchConversationMenuAction` the menu's onSelected runs. Lands on
/// the chats home first so the conversation list is mounted.
Future<void> _dispatchConversationAction(
  Inst inst,
  String gid,
  String action,
) async {
  await returnToChatsHome(inst, rounds: 4);
  await inst.foreground();
  final r = await inst.l3('l3_open_conversation_menu', {
    'conversationId': 'group_$gid',
    'action': action,
  });
  if (r['ok'] != true) {
    await inst.shot('/tmp/ui_conv_action_fail_${action}_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] l3_open_conversation_menu action=$action failed for '
      'group_$gid: $r',
    );
  }
}

/// S131 — single-instance: create a group, open its row context menu via the
/// ungated deep-link, assert the menu item keys (pin / mark-read / delete).
Future<int> runGroupConversationMenu(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GMENU-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  await _openConversationMenu(inst, gid);
  final hasPin = await inst.waitKey(
    'conversation_context_menu_pin_item',
    timeoutSecs: 8,
  );
  final hasMarkRead = await inst.waitKey(
    'conversation_context_menu_mark_read_item',
    timeoutSecs: 5,
  );
  final hasDelete = await inst.waitKey(
    'conversation_context_menu_delete_item',
    timeoutSecs: 5,
  );
  await inst.shot('/tmp/ui_group_conv_menu_${inst.name}.png');
  await _dismissContextMenu(inst);
  if (hasPin && hasMarkRead && hasDelete) {
    print(
      '[pair] PASS: real-UI group conversation context-menu surface '
      '(pin+mark_read+delete, gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group conversation menu surface '
    '(pin=$hasPin markRead=$hasMarkRead delete=$hasDelete gid=${_shortId(gid)})',
  );
  return 1;
}

/// S132 — single-instance: Pin the group row → assert isPinned → Unpin → assert
/// unpinned, via the production `pinConversation` path. Drives the menu's `pin`
/// action through the deterministic deep-link (`l3_open_conversation_menu`
/// action:'pin') instead of tapping the PopupMenuItem — flutter_skill
/// double-fires the InkWell-backed item, toggling pin twice (net no-op), which
/// is why the tap leg was previously unreliable. First the surface is verified
/// (the keyed pin item renders), then the action is dispatched.
Future<int> runGroupMenuPinUnpin(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GPIN-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  // Surface check: the real keyed pin item must render in the row menu.
  await _openConversationMenu(inst, gid);
  final hasPinItem = await inst.waitKey(
    'conversation_context_menu_pin_item',
    timeoutSecs: 8,
  );
  await _dismissContextMenu(inst);
  if (!hasPinItem) {
    await inst.shot('/tmp/ui_group_pin_nopin_${inst.name}.png');
    throw DriveError('[${inst.name}] pin item not present for $convId');
  }

  // Pin (toggle) → assert pinned → pin again (toggle) → assert unpinned.
  await _dispatchConversationAction(inst, gid, 'pin');
  final pinned = await _waitConversationPinned(inst, convId, true);
  await _dispatchConversationAction(inst, gid, 'pin');
  final unpinned = await _waitConversationPinned(inst, convId, false);

  await inst.shot('/tmp/ui_group_pin_${inst.name}.png');
  if (pinned && unpinned) {
    print(
      '[pair] PASS: real-UI group menu pin→unpin via pinConversation '
      '(gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu pin/unpin (pinned=$pinned unpinned=$unpinned '
    'gid=${_shortId(gid)})',
  );
  return 1;
}

/// S133 — single-instance: assert the Mark-as-read item surfaces + unread stays
/// 0. A single instance cannot seed group unread (own sends don't increment own
/// unread; inbound needs a peer), so this asserts the menu SURFACE + the
/// no-regression invariant, NOT a true unread>0→0 transition.
Future<int> runGroupMenuMarkRead(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GMR-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  await _openConversationMenu(inst, gid);
  final hasMarkRead = await inst.waitKey(
    'conversation_context_menu_mark_read_item',
    timeoutSecs: 8,
  );
  if (hasMarkRead) {
    await inst.tryTapKey('conversation_context_menu_mark_read_item', retries: 2);
  }
  await _dismissContextMenu(inst);

  final entry = await _conversationEntry(inst, convId);
  final unread = (entry?['unreadCount'] as num?)?.toInt() ?? 0;
  await inst.shot('/tmp/ui_group_markread_${inst.name}.png');
  if (hasMarkRead && unread == 0) {
    print(
      '[pair] PASS: real-UI group menu mark-read surface '
      '(item present; unread stays 0 single-instance, gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu mark-read (item=$hasMarkRead unread=$unread '
    'gid=${_shortId(gid)})',
  );
  return 1;
}

/// S134 — single-instance: open the group row menu → Delete → confirm → assert
/// the group conversation is gone from the sidebar.
Future<int> runGroupMenuDeleteConfirm(Inst inst, String nick) async {
  await ensureHome(inst, nick);
  await inst.waitState(
    (s) => s['isConnected'] == true,
    label: '$nick connected',
  );
  final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final created = await _createGroupViaUI(
    inst,
    'RUI-GDEL-$nonce',
    groupType: 'private',
  );
  final gid = created.groupId;
  final convId = 'group_$gid';

  // Surface check: the real keyed delete item renders in the row menu.
  await _openConversationMenu(inst, gid);
  final hasDeleteItem = await inst.waitKey(
    'conversation_context_menu_delete_item',
    timeoutSecs: 8,
  );
  await _dismissContextMenu(inst);
  if (!hasDeleteItem) {
    await inst.shot('/tmp/ui_group_del_noitem_${inst.name}.png');
    throw DriveError('[${inst.name}] delete item not present for $convId');
  }

  // Dispatch the delete action directly (avoids the flutter_skill double-fire on
  // the PopupMenuItem) — it raises the REAL confirm dialog, which the harness
  // confirms by tapping the guarded confirm button.
  await _dispatchConversationAction(inst, gid, 'delete');
  if (!await inst.waitKey(
    'delete_conversation_confirm_button',
    timeoutSecs: 10,
  )) {
    await inst.shot('/tmp/ui_group_del_nodialog_${inst.name}.png');
    throw DriveError(
      '[${inst.name}] delete-conversation confirm dialog did not open',
    );
  }
  await inst.tapKey('delete_conversation_confirm_button');

  // For a group, `deleteConversation` fires onConversationDeleted (the host
  // suppresses the row until a new message arrives) AND clears history + pin, so
  // the row leaves the sidebar.
  final gone = await _waitConversationGone(inst, convId, timeoutSecs: 20);
  await inst.shot('/tmp/ui_group_del_${inst.name}.png');
  if (gone) {
    print(
      '[pair] PASS: real-UI group menu delete+confirm removes conversation '
      '(gid=${_shortId(gid)})',
    );
    return 0;
  }
  print(
    '[pair] FAIL: group menu delete+confirm — $convId still present '
    '(gid=${_shortId(gid)})',
  );
  return 1;
}

/// S118 / S133 — two-process group: drive the TRUE unread>0 → 0 transition via
/// the row menu's Mark-as-read. The single-instance gate could only prove the
/// item renders (own sends never bump own unread). Here B sends into the group
/// while A is NOT viewing it (A's active conversation cleared), so A accrues real
/// group unread; then A marks read via the deterministic `mark_read` action and
/// the count must drop to 0 — through the production
/// `cleanConversationUnreadMessageCount` → markConversationRead path the docs
/// wrongly believed was a no-op.
Future<int> runGroupMarkReadUnread(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GMRUNREAD',
  );
  if (est == null) {
    print('[pair] FAIL: group mark-read could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    // A must NOT be the active conversation, or the inbound message auto-marks
    // read (ffi_chat_service: _activePeerId == gid → unread stays 0). Park A on
    // the chats home and force the active conversation to none.
    await returnToChatsHome(a, rounds: 4);
    await a.l3('l3_set_active_conversation', <String, dynamic>{});

    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGMRUNREAD-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      await a.shot('/tmp/ui_group_markread_seed_fail_A.png');
      print('[pair] FAIL: group mark-read seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }

    final seeded = await _waitConversationUnread(a, convId, (u) => u > 0);
    if (!seeded) {
      final entry = await _conversationEntry(a, convId);
      await a.shot('/tmp/ui_group_markread_noseed_A.png');
      print(
        '[pair] FAIL: group mark-read — unread did not accrue on A (entry=$entry)',
      );
      return 1;
    }

    await _dispatchConversationAction(a, est.groupIdA, 'mark_read');
    final cleared = await _waitConversationUnread(a, convId, (u) => u == 0);
    await a.shot('/tmp/ui_group_markread_A.png');
    if (cleared) {
      print(
        '[pair] PASS: real-UI group menu mark-read drove unread>0 → 0 '
        '(gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    final entry = await _conversationEntry(a, convId);
    print('[pair] FAIL: group mark-read — unread did not clear (entry=$entry)');
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (e) {
        print(
          '[pair] WARN failed to restore B autoAcceptGroupInvites: ${e.message}',
        );
      }
    }
  }
}

/// S122 — two-process group: clear a group's history and assert the messages are
/// gone while the conversation row survives. B sends into the group (so A holds
/// real group history), then A clears via `l3_clear_group_history` (the group
/// counterpart to the C2C-only l3_clear_history). A's group history messageCount
/// must drop to 0 AND the conversation row must remain in the sidebar (the row is
/// rebuilt from knownGroups, independent of history).
Future<int> runGroupClearHistory(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCLEAR',
  );
  if (est == null) {
    print('[pair] FAIL: group clear-history could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGCLEAR-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      print('[pair] FAIL: group clear-history seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }
    final beforeCount =
        ((await a.dumpState(conversationId: convId))['messageCount'] as num?)
            ?.toInt() ??
        0;
    if (beforeCount <= 0) {
      print(
        '[pair] FAIL: group clear-history — no history to clear '
        '(before=$beforeCount)',
      );
      return 1;
    }
    final r = await a.l3('l3_clear_group_history', {'groupId': est.groupIdA});
    if (r['ok'] != true) {
      print('[pair] FAIL: l3_clear_group_history failed: $r');
      return 1;
    }
    final emptied = await _waitGroupHistoryCount(a, convId, (c) => c == 0);
    final rowPresent = (await _conversationEntry(a, convId)) != null;
    await a.shot('/tmp/ui_group_clear_A.png');
    if (emptied && rowPresent) {
      print(
        '[pair] PASS: real-UI group clear-history emptied history, row survives '
        '(before=$beforeCount gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: group clear-history '
      '(emptied=$emptied rowPresent=$rowPresent before=$beforeCount)',
    );
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
  }
}

/// S154 — two-process group: pin the group, seed history, clear history, and
/// assert the row stays pinned. Pin and history are independent stores
/// (`clearGroupHistory` touches the history persistence + last/unread maps, never
/// the pinned set), so a clear must never unpin. Combines S132 (pin action) +
/// S122 (clear): A pins via the row menu action, B sends (A gets history), A
/// clears, then the row must remain present AND pinned with 0 messages.
Future<int> runGroupClearPreservesPin(
  Inst a,
  Inst b,
  String nickA,
  String nickB,
) async {
  final est = await _establishTwoProcessGroup(
    a,
    b,
    nickA,
    nickB,
    groupType: 'private',
    namePrefix: 'RUI-GCLRPIN',
  );
  if (est == null) {
    print('[pair] FAIL: group clear-preserves-pin could not establish a group');
    return 1;
  }
  final convId = 'group_${est.groupIdA}';
  try {
    await _dispatchConversationAction(a, est.groupIdA, 'pin');
    if (!await _waitConversationPinned(a, convId, true)) {
      await a.shot('/tmp/ui_group_clrpin_nopin_A.png');
      print('[pair] FAIL: group clear-preserves-pin — initial pin did not take');
      return 1;
    }
    final nonce = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final m = 'RUIGCLRPIN-$nonce';
    await openGroupChat(b, groupId: est.groupIdB, groupName: est.groupName);
    final bSent = await sendComposerMessage(b, m);
    final aGot = await _waitGroupMessageAnyConversation(a, m, timeoutSecs: 60);
    if (!bSent || !aGot) {
      print('[pair] FAIL: clear-preserves-pin seed (bSent=$bSent aGot=$aGot)');
      return 1;
    }
    final r = await a.l3('l3_clear_group_history', {'groupId': est.groupIdA});
    if (r['ok'] != true) {
      print('[pair] FAIL: l3_clear_group_history failed: $r');
      return 1;
    }
    final emptied = await _waitGroupHistoryCount(a, convId, (c) => c == 0);
    final stillPinned = await _waitConversationPinned(a, convId, true);
    final rowPresent = (await _conversationEntry(a, convId)) != null;
    await a.shot('/tmp/ui_group_clrpin_A.png');
    if (emptied && stillPinned && rowPresent) {
      print(
        '[pair] PASS: real-UI group clear-history preserved row + pin '
        '(gid=${_shortId(est.groupIdA)})',
      );
      return 0;
    }
    print(
      '[pair] FAIL: clear-preserves-pin '
      '(emptied=$emptied stillPinned=$stillPinned rowPresent=$rowPresent)',
    );
    return 1;
  } finally {
    if (!est.priorAutoAccept) {
      try {
        await _setAutoAcceptGroupInvites(b, false);
      } on DriveError catch (_) {}
    }
  }
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
  if (args.length == 1 && args.single == '--self-test-shell-recovery') {
    return _runShellRecoverySelfTest();
  }
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
    if (scenario == 'group_message') {
      return await runGroupMessage(a, b, nickA, nickB);
    }
    if (scenario == 'group_burst') {
      return await runGroupBurst(a, b, nickA, nickB);
    }
    if (scenario == 'group_member_list') {
      return await runGroupMemberList(a, b, nickA, nickB);
    }
    if (scenario == 'group_create') {
      // Single-instance: drive only A (B is launched-but-idle).
      return await runGroupCreate(a, nickA);
    }
    // Single-instance LOGIN + SETTINGS real-UI scenarios (drive only A).
    if (scenario == 'settings_sweep') {
      return await runSettingsSweep(a, nickA);
    }
    if (scenario == 'settings_copy_id') {
      await ensureHome(a, nickA);
      return await _settingsCopyId(a) ? 0 : 1;
    }
    if (scenario == 'settings_autologin') {
      await ensureHome(a, nickA);
      return await _settingsAutoLogin(a) ? 0 : 1;
    }
    if (scenario == 'settings_notification') {
      await ensureHome(a, nickA);
      return await _settingsNotification(a) ? 0 : 1;
    }
    if (scenario == 'settings_export_chooser') {
      await ensureHome(a, nickA);
      return await _settingsExportChooser(a) ? 0 : 1;
    }
    if (scenario == 'settings_password') {
      await ensureHome(a, nickA);
      return await _settingsPassword(a) ? 0 : 1;
    }
    if (scenario == 'settings_logout_relogin') {
      await ensureHome(a, nickA);
      return await _settingsLogoutRelogin(a) ? 0 : 1;
    }
    if (scenario == 'group_profile_open') {
      return await runGroupProfileOpen(a, nickA);
    }
    if (scenario == 'group_rename') {
      return await runGroupRename(a, nickA);
    }
    if (scenario == 'group_search') {
      return await runGroupSearch(a, nickA);
    }
    if (scenario == 'group_add_member_open') {
      return await runGroupAddMemberOpen(a, nickA);
    }
    if (scenario == 'group_add_member_picker') {
      return await runGroupAddMemberPicker(a, b, nickA, nickB);
    }
    if (scenario == 'group_conversation_menu') {
      return await runGroupConversationMenu(a, nickA);
    }
    if (scenario == 'group_menu_pin_unpin') {
      return await runGroupMenuPinUnpin(a, nickA);
    }
    if (scenario == 'group_menu_mark_read') {
      return await runGroupMenuMarkRead(a, nickA);
    }
    if (scenario == 'group_menu_delete_confirm') {
      return await runGroupMenuDeleteConfirm(a, nickA);
    }
    if (scenario == 'group_menu_mark_read_unread') {
      // Two-process: B seeds real unread on A, A marks read via the row menu.
      return await runGroupMarkReadUnread(a, b, nickA, nickB);
    }
    if (scenario == 'group_clear_history') {
      // Two-process: B seeds history, A clears it; row survives.
      return await runGroupClearHistory(a, b, nickA, nickB);
    }
    if (scenario == 'group_clear_preserves_pin') {
      // Two-process: A pins, B seeds history, A clears; row stays pinned.
      return await runGroupClearPreservesPin(a, b, nickA, nickB);
    }
    if (scenario == 'conference_message') {
      // Same two-process flow as group_message but a legacy Tox CONFERENCE.
      return await runGroupMessage(
        a,
        b,
        nickA,
        nickB,
        groupType: 'conference',
        label: 'CONF',
        namePrefix: 'RUI-CONF',
        msgPrefix: 'RUICONF',
      );
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
    await driveAddFriend(
      b,
      toxA,
      message: _defaultFriendRequestWording(scenario),
    );
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
