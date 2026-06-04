// S54 driver: friend-request custom message round-trips to the recipient.
//
// Contract under test:
//   A custom (wording) message attached to a friend request round-trips to the
//   recipient's pending friend-application list, intact and exact, and does NOT
//   silently auto-accept into the friend list.
//
// This is the FRESH base: two fresh registrations (NOT a restored pair). The
// request direction is irrelevant to the contract; per the handoff notes the
// B -> A direction is the stable one, so SENDER=B, RECIPIENT=A.
//
// Sequence:
//   1. Connect A, B. ensureReady(nickname: 'echo_live_test') both. Wait for
//      both to report isConnected.
//   2. Read both currentAccountToxId values. Fail if either is empty.
//   3. RECIPIENT=A: turn autoAcceptFriends OFF and CONFIRM it stuck before the
//      request is sent (otherwise A could auto-accept and the application item
//      never persists).
//   4. SENDER=B: send l3_add_friend_request to toxA carrying a unique nonce as
//      the custom message. Treat "already sent" as benign.
//   5. RECIPIENT=A: poll friendApplications for an entry whose userId matches
//      toxB (by Tox public key) AND whose wording == nonce EXACTLY.
//   6. ASSERT NEGATIVE: A must NOT yet have toxB as a friend (pending, not
//      accepted) — guards against auto-accept slipping through.
//   7. CLEANUP (finally): restore A's autoAcceptFriends=true.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  if (args.length < 2) {
    print('usage: drive_fixture_c_custom_message.dart <ws_uri_A> <ws_uri_B>');
    return 64;
  }
  final a = await _PairDriver.connect('A', args[0]);
  final b = await _PairDriver.connect('B', args[1]);
  var restoreAutoAccept = false;
  try {
    await a.ensureReady(nickname: 'echo_live_test');
    await b.ensureReady(nickname: 'echo_live_test');
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids after registration: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-custom-msg] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    // RECIPIENT=A: autoAcceptFriends must be OFF and confirmed BEFORE the
    // request is sent, else A auto-accepts and no application item persists.
    restoreAutoAccept = true;
    await a.setSetting('autoAcceptFriends', 'false');
    await a.waitForAutoAcceptFriends(expected: false, timeoutSecs: 10);
    print('[fixture-c-custom-msg] A autoAcceptFriends=false confirmed');

    final nonce = 'S54-CUSTOM-${DateTime.now().microsecondsSinceEpoch}';

    // SENDER=B: friend request to A carrying the custom message.
    await b.addFriendRequest(toxA, message: nonce);

    // RECIPIENT=A: the custom message must arrive in the pending list, intact.
    final wording = await a.waitForFriendApplicationWording(
      fromUserId: toxB,
      wording: nonce,
      timeoutSecs: 120,
    );

    // ASSERT NEGATIVE: it must be a pending application, not an accepted
    // friend. If toxB is already a friend, autoAccept slipped through.
    if (await a.hasFriend(toxB)) {
      throw _DriveError(
        'NEGATIVE assertion failed: B is already in A\'s friend list — '
        'autoAcceptFriends=false did not prevent auto-accept',
      );
    }

    print('[fixture-c-custom-msg] observed wording: "$wording"');
    print('[fixture-c-custom-msg] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-custom-msg] ERROR: ${e.message}');
    return 1;
  } finally {
    if (restoreAutoAccept) {
      try {
        await a.setSetting('autoAcceptFriends', 'true');
        print('[fixture-c-custom-msg] cleanup: A autoAcceptFriends restored');
      } catch (e) {
        print('[fixture-c-custom-msg] cleanup: restore autoAccept failed: $e');
      }
    }
    await a.dispose();
    await b.dispose();
  }
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

class _PairDriver {
  _PairDriver(this.name, this.vm, this.isolateId);

  final String name;
  final VmService vm;
  final String isolateId;

  static Future<_PairDriver> connect(String name, String wsUri) async {
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final d = _PairDriver(name, vm, isolateId);
    await d.waitForExtension('ext.mcp.toolkit.l3_dump_state', timeoutSecs: 60);
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_register_account',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_set_setting',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_add_friend_request',
      timeoutSecs: 60,
    );
    return d;
  }

  Future<void> dispose() => vm.dispose();

  Future<void> waitForExtension(String name, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      final ext = iso.extensionRPCs ?? const <String>[];
      if (ext.contains(name)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _DriveError('[$name] extension $name not registered');
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

  Future<Map<String, dynamic>> dumpState({String? userId}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      userId == null
          ? const <String, Object?>{}
          : <String, Object?>{'userId': userId},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<String> currentToxId() async {
    final s = await dumpState();
    return (s['currentAccountToxId']?.toString() ?? '').trim();
  }

  Future<void> ensureReady({required String nickname}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-custom-msg][$name] session already ready');
      return;
    }
    print('[fixture-c-custom-msg][$name] registering via l3_register_account');
    final resp = await _call(
      'ext.mcp.toolkit.l3_register_account',
      <String, Object?>{'nickname': nickname},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_register_account failed: ${json['error']}');
    }

    await _waitForSessionReady();
  }

  Future<void> _waitForSessionReady() async {
    await _retry(
      () async {
        final s = await dumpState();
        if (s['sessionReady'] != true) {
          throw _DriveError('sessionReady still false');
        }
      },
      attempts: 60,
      intervalMs: 1000,
      label: 'wait sessionReady',
    );
  }

  Future<void> setSetting(String key, String value) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_setting',
      <String, Object?>{'key': key, 'value': value},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_set_setting $key=$value failed: ${json['error']}',
      );
    }
  }

  Future<void> waitForAutoAcceptFriends({
    required bool expected,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      if (state['autoAcceptFriends'] == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] autoAcceptFriends did not become $expected',
    );
  }

  Future<void> addFriendRequest(String toxId, {required String message}) async {
    print(
      '[fixture-c-custom-msg][$name] sending friend request '
      '${toxId.substring(0, 16)}... with custom message',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_add_friend_request',
      <String, Object?>{'userId': toxId, 'message': message},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      final resultInfo = json['resultInfo']?.toString().toLowerCase() ?? '';
      if (resultInfo.contains('already sent')) {
        print('[fixture-c-custom-msg][$name] friend request already pending');
        return;
      }
      throw _DriveError(
        '[$name] l3_add_friend_request failed: ${json['error']}',
      );
    }
  }

  /// Polls the pending friend-application list for an entry from [fromUserId]
  /// (matched by Tox public key) whose wording equals [wording] exactly.
  /// Returns the observed wording on success; throws on timeout.
  Future<String> waitForFriendApplicationWording({
    required String fromUserId,
    required String wording,
    required int timeoutSecs,
  }) async {
    final wantPk = _toxPublicKey(fromUserId);
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    List<dynamic> lastApps = const <dynamic>[];
    Object? lastCount;
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      lastApps = (state['friendApplications'] as List?) ?? const <dynamic>[];
      lastCount = state['friendApplicationCount'];
      for (final app in lastApps) {
        if (app is! Map) continue;
        final appUserId = app['userId']?.toString() ?? '';
        if (_toxPublicKey(appUserId) != wantPk) continue;
        final appWording = app['wording']?.toString() ?? '';
        if (appWording == wording) {
          return appWording;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    print(
      '[fixture-c-custom-msg][$name] last friendApplications snapshot: '
      '$lastApps (friendApplicationCount=$lastCount)',
    );
    throw _DriveError(
      '[$name] friend application with wording "$wording" from '
      '${fromUserId.substring(0, 16)} timed out',
    );
  }

  Future<bool> hasFriend(String userId) async {
    final wantPk = _toxPublicKey(userId);
    final state = await dumpState();
    final friends = (state['friends'] as List?) ?? const <dynamic>[];
    for (final friend in friends) {
      if (friend is! Map) continue;
      final friendId = friend['userId']?.toString() ?? '';
      if (_toxPublicKey(friendId) == wantPk) {
        return true;
      }
    }
    return false;
  }

  Future<void> waitForConnected({required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      if (state['isConnected'] == true) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError('[$name] isConnected did not become true');
  }
}

String _toxPublicKey(String userId) {
  final normalized = userId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
}

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final vmObj = await vm.getVM();
    final isolates = vmObj.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
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
