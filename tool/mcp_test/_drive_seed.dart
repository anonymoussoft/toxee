// Echo peer fixture — Phase 4 marionette driver.
//
// Runs the UI seeding flow from outside the app process:
//   1. Connect to the Dart VM service (URI read from $1).
//   2. Find the main isolate.
//   3. Call ext.flutter.marionette.* extensions to drive UI.
//
// Sequence (per v2.3 §4 "regen_echo_peer_seed.sh — generate snapshot"):
//   - Wait for Login page → tap "Register new account" card (by text).
//   - Enter nickname into RegisterPage's nickname field (by key OR by type).
//   - Tap register button.
//   - Branch: if FirstRunBackupWizard mounts, drive it through the
//     "I'll do it later" + dismiss-confirm path; else proceed.
//   - Wait for HomePage.
//   - Tap contacts tab → menu → "Add contact".
//   - Enter peer_id into AddFriendDialog input.
//   - Submit.
//   - Wait for the AddFriendDialog to close, then poll Prefs until the friend
//     lands under local_friends_<accountPrefix>.
//   - Send 3 ping messages via the L3 debug tool surface and wait for each
//     echo in persisted history (faster + more deterministic than driving the
//     desktop composer / conversation routing through UI gestures).
//
// Usage:
//   dart run tool/mcp_test/_drive_seed.dart <ws_uri> <peer_id> [<nickname>]
//
// On success exits 0. On any unrecoverable failure exits non-zero with a
// reason on stderr. Intermediate progress on stdout (parsed by regen script).
//
// Reference: /tmp/codex_round7/echo_peer_v2.3.md §4 (regen).
// Reference: ValueKey conventions inherited from the project; if a key is not
// found this driver falls back to text/type matchers via marionette's
// interactiveElements RPC. For post-submit verification the driver also polls
// macOS SharedPreferences (`defaults read com.toxee.app ...`) because the
// submitted peer_id remains visible in the dialog input until the dialog
// ACTUALLY closes, which makes raw "find the peer_id text" checks false-green.

// `vm_service` is a transitive dep of the project (pulled in by Flutter
// tooling). Adding it to pubspec.yaml would force a manual pin we don't want
// to maintain; relying on transitive is intentional for this tool-only script.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

const String _argsHelp =
    'Usage: dart run tool/mcp_test/_drive_seed.dart <ws_uri> <peer_id> [<nickname>]';

// Localized strings the driver looks for on each page. Driving by text is
// brittle to i18n changes; if these labels change, update them here.
const List<String> _registerButtonLabels = <String>[
  '注册新账号',
  'Register new account',
  'Register New Account',
];
const List<String> _addContactMenuLabels = <String>['Add contact', '添加联系人'];

Future<int> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln(_argsHelp);
    return 64;
  }
  final wsUri = args[0];
  final peerId = args[1];
  final nickname = args.length >= 3 ? args[2] : 'echo_seeded_test';

  if (peerId.length != 76) {
    stderr.writeln('peer_id must be 76 hex chars; got length=${peerId.length}');
    return 65;
  }

  stdout.writeln('[drive] connecting to $wsUri');
  late VmService vm;
  try {
    vm = await vmServiceConnectUri(wsUri);
  } catch (e) {
    stderr.writeln('[drive] vm connect failed: $e');
    return 70;
  }

  try {
    final isolateId = await _findMainIsolate(vm);
    stdout.writeln('[drive] isolate=$isolateId');

    final driver = _Driver(vm, isolateId);

    // Each high-level step has a generous timeout — driving is human-paced.
    await driver.waitForExtension(
      'ext.flutter.marionette.tap',
      timeoutSecs: 60,
    );

    stdout.writeln('[drive] step: tap Register card');
    await _retry(
      () => driver.tapText(_registerButtonLabels),
      attempts: 30,
      intervalMs: 1000,
      label: 'tap register card',
    );

    stdout.writeln('[drive] step: enter nickname');
    await _retry(
      () => driver.enterTextByKey('register_page_nickname_field', nickname),
      attempts: 20,
      intervalMs: 1000,
      label: 'enter nickname',
    );

    stdout.writeln('[drive] step: tap register button');
    await _retry(
      () => driver.tapKey('register_page_register_button'),
      attempts: 20,
      intervalMs: 1000,
      label: 'tap register button',
    );

    // After register, registration MAY route through FirstRunBackupWizard
    // (gated by FeatureFlags.enableFirstRunBackupWizard, default TRUE). The
    // wizard blocks navigation to HomePage until the user either exports
    // their .tox file or explicitly acknowledges the data-loss consequence.
    // For the seed driver we acknowledge the dismiss path — we don't want
    // to write a .tox file from the seeded fixture run.
    //
    // Strategy: wait for EITHER the wizard's "later" button OR HomePage's
    // sidebar to appear, whichever comes first. If we see the wizard,
    // drive it (tap later → tap confirm) and then wait for HomePage.
    stdout.writeln('[drive] step: wait for HomePage or backup wizard');
    final foundWizard = await _waitForFirstOf(
      driver,
      keys: const ['firstRunBackupWizard.laterButton', 'sidebar_contacts_tab'],
      attempts: 60,
      intervalMs: 1000,
      label: 'wizard-or-home',
    );
    if (foundWizard == 'firstRunBackupWizard.laterButton') {
      stdout.writeln('[drive] step: drive FirstRunBackupWizard (skip path)');
      await driver.tapKey('firstRunBackupWizard.laterButton');
      // Confirmation dialog renders on next frame; tap the destructive
      // confirm button by stable key (codex Round 17 P1 — text-based
      // matching was locale-fragile; the actual zh_Hans label is
      // `我已了解，继续` not `我明白，继续`). The key is wired at
      // lib/ui/widgets/first_run_backup_wizard.dart:202.
      await _retry(
        () => driver.tapKey('firstRunBackupWizard.confirmDismissButton'),
        attempts: 20,
        intervalMs: 500,
        label: 'tap wizard dismiss confirm',
      );
      stdout.writeln('[drive] step: wait for HomePage (post-wizard)');
      await _retry(
        () => driver.findElementByKey('sidebar_contacts_tab'),
        attempts: 60,
        intervalMs: 1000,
        label: 'find sidebar_contacts_tab',
      );
    }

    stdout.writeln('[drive] step: tap contacts tab');
    await driver.tapKey('sidebar_contacts_tab');

    stdout.writeln('[drive] step: tap new entry menu');
    await _retry(
      () => driver.tapKey('new_entry_menu_button'),
      attempts: 20,
      intervalMs: 500,
      label: 'tap new_entry_menu_button',
    );
    // F14 popup menu animation wait per v2.3 spec.
    await Future<void>.delayed(const Duration(milliseconds: 600));

    stdout.writeln('[drive] step: tap "Add contact"');
    try {
      await driver.tapKey('new_entry_add_contact_item');
    } catch (_) {
      await driver.tapText(_addContactMenuLabels);
    }

    stdout.writeln('[drive] step: enter peer_id');
    await _retry(
      () => driver.enterTextByKey('add_friend_id_input', peerId),
      attempts: 30,
      intervalMs: 500,
      label: 'enter add_friend_id_input',
    );

    stdout.writeln('[drive] step: tap submit');
    await driver.tapKey('add_friend_submit_button');

    stdout.writeln('[drive] step: wait for add-friend dialog to close');
    await _retry(
      () => driver.ensureKeyAbsent('add_friend_id_input'),
      attempts: 60,
      intervalMs: 1000,
      label: 'wait add_friend dialog close',
    );

    stdout.writeln('[drive] step: wait for local_friends persistence');
    await _waitForLocalFriendPersisted(peerId);

    stdout.writeln('[drive] step: wait for L3 debug tools');
    await driver.waitForExtension(
      'ext.mcp.toolkit.l3_send_text',
      timeoutSecs: 60,
    );
    await driver.waitForExtension(
      'ext.mcp.toolkit.l3_dump_state',
      timeoutSecs: 60,
    );

    // Send 3 ping messages via the deterministic L3 tool path. This hits the
    // real toxee send pipeline while avoiding the desktop-only Enter-to-send
    // gesture and the conversation-row routing flake.
    for (var i = 1; i <= 3; i++) {
      final text = 'ping $i';
      stdout.writeln('[drive] step: send "$text"');
      await _retry(
        () => driver.l3SendText(userId: peerId, text: text),
        attempts: 30,
        intervalMs: 1000,
        label: 'l3_send_text $text',
      );
      stdout.writeln('[drive] step: wait for echo of "$text"');
      await _retry(
        () => driver.l3WaitForPersistedTextCount(
          userId: peerId,
          text: text,
          atLeast: 2,
        ),
        attempts: 45,
        intervalMs: 1000,
        label: 'echo of $text',
      );
    }

    stdout.writeln('[drive] DONE');
    return 0;
  } on _DriveError catch (e) {
    stderr.writeln('[drive] ERROR: ${e.message}');
    return 71;
  } catch (e, st) {
    stderr.writeln('[drive] UNEXPECTED: $e\n$st');
    return 72;
  } finally {
    await vm.dispose();
  }
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
  @override
  String toString() => message;
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final vmObj = await vm.getVM();
    final isolates = vmObj.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      // Prefer the "main" isolate if Flutter named it; otherwise first.
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) {
          return iso.id!;
        }
      }
      return isolates.first.id!;
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  throw _DriveError('no isolate appeared on VM');
}

Future<T> _retry<T>(
  Future<T> Function() body, {
  required int attempts,
  required int intervalMs,
  required String label,
}) async {
  Object? lastErr;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e) {
      lastErr = e;
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }
  throw _DriveError('retry exhausted ($label): $lastErr');
}

// Polls `interactiveElements` until ANY of the supplied keys appears in the
// widget tree, then returns the matched key. Throws after `attempts`. Used
// for branch-on-first-render flows (e.g. wizard vs HomePage after register).
Future<String> _waitForFirstOf(
  _Driver driver, {
  required List<String> keys,
  required int attempts,
  required int intervalMs,
  required String label,
}) async {
  for (var i = 0; i < attempts; i++) {
    for (final k in keys) {
      try {
        await driver.findElementByKey(k);
        return k;
      } catch (_) {
        // keep looking
      }
    }
    await Future<void>.delayed(Duration(milliseconds: intervalMs));
  }
  throw _DriveError('first-of timed out ($label): none of $keys appeared');
}

Future<void> _waitForLocalFriendPersisted(String peerId) async {
  final expectedPubkey = peerId.substring(0, 64).toUpperCase();
  String? lastAccount;
  String? lastFriends;
  for (var i = 0; i < 90; i++) {
    final account = await _defaultsRead('flutter.current_account_tox_id');
    lastAccount = account;
    if (account != null && account.length >= 16) {
      final prefix = account.substring(0, 16).toUpperCase();
      final friends = await _defaultsRead('flutter.local_friends_$prefix');
      lastFriends = friends;
      if (friends != null && friends.toUpperCase().contains(expectedPubkey)) {
        return;
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  throw _DriveError(
    'local_friends persistence timed out: current_account_tox_id=$lastAccount '
    'local_friends=${lastFriends ?? "<missing>"}',
  );
}

Future<String?> _defaultsRead(String key) async {
  final result = await Process.run('defaults', ['read', 'com.toxee.app', key]);
  if (result.exitCode != 0) return null;
  final out = (result.stdout as String).trim();
  return out.isEmpty ? null : out;
}

class _Driver {
  _Driver(this.vm, this.isolateId);
  final VmService vm;
  final String isolateId;

  // Wait until a particular service extension is registered on the isolate.
  Future<void> waitForExtension(String name, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      final ext = iso.extensionRPCs ?? const <String>[];
      if (ext.contains(name)) {
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _DriveError('extension $name not registered within ${timeoutSecs}s');
  }

  Future<Response> _call(String method, Map<String, Object?> args) {
    final stringArgs = <String, String>{
      for (final entry in args.entries) entry.key: entry.value.toString(),
    };
    return vm.callServiceExtension(
      method,
      isolateId: isolateId,
      args: stringArgs,
    );
  }

  Future<void> tapKey(String key) async {
    await _call('ext.flutter.marionette.tap', <String, Object?>{'key': key});
  }

  Future<void> tapText(List<String> texts) async {
    Object? lastErr;
    for (final t in texts) {
      try {
        await _call('ext.flutter.marionette.tap', <String, Object?>{'text': t});
        return;
      } catch (e) {
        lastErr = e;
      }
    }
    throw _DriveError('no text matched in $texts: $lastErr');
  }

  Future<void> enterTextByKey(String key, String input) async {
    await _call('ext.flutter.marionette.enterText', <String, Object?>{
      'key': key,
      'input': input,
    });
  }

  // Returns when the element is found, otherwise throws.
  Future<void> findElementByKey(String key) async {
    final resp = await _call(
      'ext.flutter.marionette.interactiveElements',
      const <String, Object?>{},
    );
    final json = resp.json ?? const <String, dynamic>{};
    final elements = (json['elements'] as List?) ?? const <dynamic>[];
    for (final e in elements) {
      if (e is Map && e['key'] == key) {
        return;
      }
    }
    throw _DriveError('key not found: $key');
  }

  Future<void> ensureKeyAbsent(String key) async {
    final resp = await _call(
      'ext.flutter.marionette.interactiveElements',
      const <String, Object?>{},
    );
    final json = resp.json ?? const <String, dynamic>{};
    final elements = (json['elements'] as List?) ?? const <dynamic>[];
    for (final e in elements) {
      if (e is Map && e['key'] == key) {
        throw _DriveError('key still present: $key');
      }
    }
  }

  Future<void> l3SendText({
    required String userId,
    required String text,
  }) async {
    final resp = await _call('ext.mcp.toolkit.l3_send_text', <String, Object?>{
      'userId': userId,
      'text': text,
    });
    final json = resp.json ?? const <String, dynamic>{};
    if (json['ok'] != true) {
      throw _DriveError(
        'l3_send_text not ready: ${json['error'] ?? resp.json ?? resp}',
      );
    }
  }

  Future<void> l3WaitForPersistedTextCount({
    required String userId,
    required String text,
    required int atLeast,
  }) async {
    final resp = await _call('ext.mcp.toolkit.l3_dump_state', <String, Object?>{
      'userId': userId,
    });
    final json = resp.json ?? const <String, dynamic>{};
    final messages = (json['messages'] as List?) ?? const <dynamic>[];
    var count = 0;
    for (final m in messages) {
      if (m is Map && (m['text']?.toString() ?? '') == text) {
        count++;
      }
    }
    if (count < atLeast) {
      throw _DriveError('persisted "$text" count=$count, need >= $atLeast');
    }
  }
}
