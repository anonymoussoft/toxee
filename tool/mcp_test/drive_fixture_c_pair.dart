// Minimal end-to-end driver for the Fixture C spike.
//
// Sequence:
//   1. Ensure both A and B are registered/logged in (register if needed).
//   2. Read both currentAccountToxId values from l3_dump_state.
//   3. For fresh mode, drive Add Friend from B to A and accept on A.
//   4. Wait until both sides see the peer online.
//   5. Verify A -> B ping and B -> A pong via l3_send_text + l3_dump_state.
//
// This intentionally stops short of being a general reusable runner; it is
// the disposable "can we really do launch A + launch B + add friend +
// ping/pong?" spike implementation.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'fixture_c_bootstrap.dart';

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
      'usage: drive_fixture_c_pair.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path/to/paired_for_e2e_manifest.json]',
    );
    return 64;
  }
  final fixture = fixtureManifestPath == null
      ? null
      : await _FixtureManifest.load(fixtureManifestPath);
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  try {
    await a.ensureReady(nickname: 'echo_live_test', fixture: fixture?.a);
    await b.ensureReady(nickname: 'echo_live_test', fixture: fixture?.b);
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // Full-mesh loopback bootstrap so same-host instances discover each other as
    // NGC peers (the public DHT alone is slow/flaky for fresh groups + macOS
    // sandbox blocks local discovery). Benefits every gate that boots through
    // this shared pair driver, and the bootstrap persists in the running
    // instances for any follow-on scenario driver.
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.isolateId),
      BootstrapTarget('B', b.vm, b.isolateId),
    ]);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids after registration: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c] toxA=${toxA.substring(0, 16)}... toxB=${toxB.substring(0, 16)}...',
    );

    if (fixture == null) {
      await b.addFriendRequest(toxA);
      await a.waitForFriendApplication(fromUserId: toxB, timeoutSecs: 120);
      await _retry(
        () => a.acceptFriend(toxB),
        attempts: 20,
        intervalMs: 1000,
        label: 'A accept friend B',
      );
    } else {
      print('[fixture-c] using restored paired fixture; skipping friend setup');
    }
    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final ping = 'fixture-c-ping-${DateTime.now().microsecondsSinceEpoch}';
    await a.sendText(toxB, ping);
    await b.waitForInboundText(fromUserId: toxA, text: ping, timeoutSecs: 90);
    print('[fixture-c] A -> B ping delivered');

    final pong = 'fixture-c-pong-${DateTime.now().microsecondsSinceEpoch}';
    await b.sendText(toxA, pong);
    await a.waitForInboundText(fromUserId: toxB, text: pong, timeoutSecs: 90);
    print('[fixture-c] B -> A pong delivered');

    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c] ERROR: ${e.message}');
    return 1;
  } finally {
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
      'ext.mcp.toolkit.l3_boot_existing_account',
      timeoutSecs: 60,
    );
    for (final ext in fixtureCBootstrapExtensions) {
      await d.waitForExtension(ext, timeoutSecs: 60);
    }
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

  Future<void> ensureReady({
    required String nickname,
    _FixtureAccount? fixture,
  }) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c][$name] session already ready');
      return;
    }
    if (fixture != null) {
      print(
        '[fixture-c][$name] booting restored account '
        '${fixture.toxId.substring(0, 16)}...',
      );
      final resp = await _call(
        'ext.mcp.toolkit.l3_boot_existing_account',
        <String, Object?>{'toxId': fixture.toxId, 'nickname': fixture.nickname},
      );
      final json = (resp.json ?? const <String, dynamic>{})
          .cast<String, dynamic>();
      if (json['ok'] != true) {
        final error = json['error'];
        throw _DriveError('[$name] l3_boot_existing_account failed: $error');
      }
      await _waitForSessionReady();
      return;
    }
    print('[fixture-c][$name] registering via l3_register_account');
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

  Future<void> acceptFriend(String userId) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_accept_friend_request',
      <String, Object?>{'userId': userId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_accept_friend_request failed: ${json['error']}',
      );
    }
  }

  Future<void> addFriendRequest(String toxId) async {
    print(
      '[fixture-c][$name] sending friend request ${toxId.substring(0, 16)}...',
    );
    final resp = await _call(
      'ext.mcp.toolkit.l3_add_friend_request',
      <String, Object?>{'userId': toxId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      final resultInfo = json['resultInfo']?.toString().toLowerCase() ?? '';
      if (resultInfo.contains('already sent')) {
        print('[fixture-c][$name] friend request already pending');
        return;
      }
      throw _DriveError(
        '[$name] l3_add_friend_request failed: ${json['error']}',
      );
    }
  }

  Future<void> sendText(String userId, String text) async {
    final resp = await _call('ext.mcp.toolkit.l3_send_text', <String, Object?>{
      'userId': userId,
      'text': text,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_send_text failed: ${json['error']}');
    }
  }

  Future<void> waitForInboundText({
    required String fromUserId,
    required String text,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(userId: fromUserId);
      final msgs = (state['messages'] as List?) ?? const <dynamic>[];
      for (final m in msgs) {
        if (m is Map && m['text']?.toString() == text && m['isSelf'] == false) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final friend = await describeFriend(fromUserId);
    throw _DriveError(
      '[$name] inbound "$text" from ${fromUserId.substring(0, 16)} timed out; '
      'friend=$friend',
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

  Future<void> waitForFriendApplication({
    required String fromUserId,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      final apps = (state['friendApplications'] as List?) ?? const <dynamic>[];
      for (final app in apps) {
        if (app is Map &&
            (app['userId']?.toString() ?? '').startsWith(
              fromUserId.substring(0, 64),
            )) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] friend application from ${fromUserId.substring(0, 16)} timed out',
    );
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
