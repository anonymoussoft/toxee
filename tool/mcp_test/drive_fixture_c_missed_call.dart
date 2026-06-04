// End-to-end driver for the S77 "missed incoming call (two processes)" L3
// scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends.
// When a manifest is supplied this driver BOOTS both restored accounts itself
// (via l3_boot_existing_account), so the gate needs no separate boot step.
//
// It places a call from A to B, confirms B sees the incoming ring, then
// deliberately leaves the call UNANSWERED. The TUICallKit ring timeout is 30s
// (tuicallkit_adapter.dart:145 `timeout: 30`); when an incoming call is never
// answered, BOTH caller and callee transition call.state 'ringing' -> 'ended'
// (endReason timeout). This driver asserts that missed-call teardown.
//
// Sequence:
//   1. Connect A and B; ensureReady(fixture) for both; waitForConnected; then
//      waitForFriendOnline both ways; resolve toxA/toxB.
//   2. A: startCall(toxB, video:false) via l3_start_call. Assert ok.
//   3. B: waitForCallStateAny({'ringing'}, 30s) — confirm B sees the incoming
//      ring. PASS A1 (ring observed).
//   4. DO NOT answer. Poll for the ring timeout: A and B each
//      waitForCallStateAny({'ended','idle'}, 60s) (30s ring timeout + slack).
//      PASS A2 (both ended without answer = missed).
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_missed_call.dart \
//       <ws_uri_A> <ws_uri_B> --fixture-manifest path/to/manifest.json

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  final positional = <String>[];
  String? fixtureManifestPath;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      fixtureManifestPath = args[++i];
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_missed_call.dart <ws_uri_A> <ws_uri_B> '
      '--fixture-manifest path/to/paired_for_e2e_manifest.json',
    );
    return 64;
  }
  final fixture = fixtureManifestPath == null
      ? null
      : await _FixtureManifest.load(fixtureManifestPath);
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  try {
    if (fixture != null) {
      await a.ensureReady(fixture: fixture.a);
      await b.ensureReady(fixture: fixture.b);
    } else {
      print('[fixture-c-missed-call] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-missed-call] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    // 2. A places an audio call to B.
    await a.startCall(toxB, video: false);
    print('[fixture-c-missed-call] A started call to B (audio)');

    // 3. B must see the incoming ring.
    await b.waitForCallStateAny({'ringing'}, timeoutSecs: 30);
    print('[fixture-c-missed-call] PASS A1 ringing');

    // 4. B never answers. The native ToxAV ring has NO auto-timeout in this
    //    app, so a "missed call" is realized when the CALLER cancels the
    //    unanswered ring: A hangs up while B is still ringing. Give B a few
    //    seconds of genuine ringing first, then A cancels.
    await Future<void>.delayed(const Duration(seconds: 5));
    // Confirm B is still ringing (truly unanswered) right before the cancel.
    await b.waitForCallStateAny({'ringing'}, timeoutSecs: 5);
    await a.callAction('hangup');
    print('[fixture-c-missed-call] A cancelled the unanswered call');

    // 5. Both sides tear down — B's incoming ring ended without B accepting
    //    (a missed incoming call from B's side).
    await a.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 30);
    await b.waitForCallStateAny({'ended', 'idle'}, timeoutSecs: 30);
    print('[fixture-c-missed-call] PASS A2 missed (incoming ring ended unanswered)');

    print('[fixture-c-missed-call] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-missed-call] ERROR: ${e.message}');
    await _dumpCallObjects(a, b);
    return 1;
  } catch (e) {
    print('[fixture-c-missed-call] ERROR: $e');
    await _dumpCallObjects(a, b);
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

Future<void> _dumpCallObjects(_PairDriver a, _PairDriver b) async {
  try {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    print('[fixture-c-missed-call] A.call=${aState['call']}');
    print('[fixture-c-missed-call] B.call=${bState['call']}');
  } catch (e) {
    print('[fixture-c-missed-call] (could not dump call objects: $e)');
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
    await d.waitForExtension('ext.mcp.toolkit.l3_start_call', timeoutSecs: 60);
    await d.waitForExtension('ext.mcp.toolkit.l3_call_action', timeoutSecs: 60);
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

  Future<Map<String, dynamic>> dumpState({String? conversationId}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      conversationId == null
          ? const <String, Object?>{}
          : <String, Object?>{'conversationId': conversationId},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<String> currentToxId() async {
    final s = await dumpState();
    return (s['currentAccountToxId']?.toString() ?? '').trim();
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-missed-call][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-missed-call][$name] booting restored account '
      '${fixture.toxId.substring(0, 16)}...',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_boot_existing_account',
      <String, Object?>{'toxId': fixture.toxId, 'nickname': fixture.nickname},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_boot_existing_account failed: ${json['error']}',
      );
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

  Future<void> startCall(String userId, {required bool video}) async {
    final resp = await _call('ext.mcp.toolkit.l3_start_call', <String, Object?>{
      'userId': userId,
      'video': video,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_start_call failed: ${json['error']}');
    }
  }

  Future<void> callAction(String action) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_call_action',
      <String, Object?>{'action': action},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_call_action($action) failed: ${json['error']}',
      );
    }
  }

  Future<void> waitForCallState(
    String state, {
    required int timeoutSecs,
  }) async {
    await waitForCallStateAny({state}, timeoutSecs: timeoutSecs);
  }

  Future<void> waitForCallStateAny(
    Set<String> states, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final s = await dumpState();
      final call = (s['call'] as Map?)?.cast<String, dynamic>();
      final current = call?['state']?.toString();
      if (current != null && states.contains(current)) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] call state not in $states within ${timeoutSecs}s',
    );
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

  Future<void> waitForFriendOnline({
    required String userId,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final friend = await _findFriend(userId);
      if (friend != null && friend['online'] == true) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final friend = await describeFriend(userId);
    throw _DriveError(
      '[$name] friend ${userId.substring(0, 16)} did not become online; '
      'friend=$friend',
    );
  }

  Future<String> describeFriend(String userId) async {
    final friend = await _findFriend(userId);
    return friend?.toString() ?? '<not in friend list>';
  }

  Future<Map<String, dynamic>?> _findFriend(String userId) async {
    final wantPk = _toxPublicKey(userId);
    final state = await dumpState();
    final friends = (state['friends'] as List?) ?? const <dynamic>[];
    for (final friend in friends) {
      if (friend is! Map) continue;
      final friendId = friend['userId']?.toString() ?? '';
      if (_toxPublicKey(friendId) == wantPk) {
        return Map<String, dynamic>.from(friend);
      }
    }
    return null;
  }
}

String _toxPublicKey(String userId) {
  final normalized = userId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
}

class _FixtureManifest {
  _FixtureManifest({required this.a, required this.b});

  final _FixtureAccount a;
  final _FixtureAccount b;

  static Future<_FixtureManifest> load(String path) async {
    final file = File(path);
    final raw = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final instances = (raw['instances'] as Map).cast<String, dynamic>();
    return _FixtureManifest(
      a: _FixtureAccount.fromJson((instances['A'] as Map).cast()),
      b: _FixtureAccount.fromJson((instances['B'] as Map).cast()),
    );
  }
}

class _FixtureAccount {
  _FixtureAccount({required this.toxId, required this.nickname});

  final String toxId;
  final String nickname;

  factory _FixtureAccount.fromJson(Map<dynamic, dynamic> json) {
    final toxId = (json['tox_id'] ?? '').toString().trim();
    final nickname = (json['nickname'] ?? '').toString().trim();
    if (toxId.isEmpty || nickname.isEmpty) {
      throw _DriveError('fixture manifest account missing tox_id/nickname');
    }
    return _FixtureAccount(toxId: toxId, nickname: nickname);
  }
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
