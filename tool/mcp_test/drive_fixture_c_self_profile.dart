// End-to-end driver for the S52 "self profile change propagates to a friend"
// L3 scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends. A
// changes its OWN Tox nickname via l3_set_self_profile; the paired friend B
// observes the new nickname on its friend-list entry for A, riding the live
// Tox `friend_name` callback over the established DHT connection.
//
// NOTE: avatar propagation (a kind-1 / TOX_FILE_KIND_AVATAR file transfer) is a
// documented FOLLOW-UP and is NOT covered by this driver — only the nickname
// leg is gated here.
//
// Sequence:
//   1. Connect A and B; ensureReady (boot restored accounts); waitForConnected
//      both; resolve toxA/toxB via currentAccountToxId.
//   2. waitForFriendOnline both directions (A sees B, B sees A) so the
//      friend_name callback can ride a live connection.
//   3. Baseline: B's friend entry for A (matched by public key) — record its
//      current nickName ("before"); FAIL if A is not in B's friend list.
//   4. Build a per-run nonce nickname S52-After-<microseconds>; on A call
//      l3_set_self_profile(nickname: newNick); assert {ok:true}.
//   5. Poll B every 1s up to 120s until A's friend entry has nickName==newNick.
//      On timeout, print the last friends snapshot + before/after and throw.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_self_profile.dart \
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
      'usage: drive_fixture_c_self_profile.dart <ws_uri_A> <ws_uri_B> '
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
      print(
        '[fixture-c-self-profile] no manifest; assuming both sessions ready',
      );
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-self-profile] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    // friend_name callback only rides a live connection — wait both ways.
    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    // 3. Baseline: B's friend entry for A (matched by public key).
    final beforeFriend = await b.findFriend(toxA);
    if (beforeFriend == null) {
      throw _DriveError(
        'A (${toxA.substring(0, 16)}...) is not in B\'s friend list; '
        'cannot baseline. friends=${await b.describeFriends()}',
      );
    }
    final beforeNick = beforeFriend['nickName']?.toString() ?? '';
    print('[fixture-c-self-profile] baseline B sees A nickName="$beforeNick"');

    // 4. Nonce-based new nickname; mutate A's own profile.
    final newNick =
        'S52-After-${DateTime.now().microsecondsSinceEpoch}';
    print('[fixture-c-self-profile] setting A nickname -> "$newNick"');
    await a.setSelfProfileNickname(newNick);

    // 5. Poll B until its friend entry for A reflects the new nickname.
    final ok = await b.waitForFriendNickName(
      userId: toxA,
      expectedNickName: newNick,
      timeoutSecs: 120,
    );
    if (!ok) {
      final lastFriends = await b.describeFriends();
      throw _DriveError(
        'B never observed A\'s new nickname; '
        'before="$beforeNick" after="$newNick"; '
        'last friends snapshot=$lastFriends',
      );
    }

    print(
      '[fixture-c-self-profile] PASS: B observed A nickName change '
      '"$beforeNick" -> "$newNick"',
    );
    print('[fixture-c-self-profile] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-self-profile] ERROR: ${e.message}');
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
      'ext.mcp.toolkit.l3_set_self_profile',
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

  Future<Map<String, dynamic>> dumpState() async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_dump_state',
      const <String, Object?>{},
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
      print('[fixture-c-self-profile][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-self-profile][$name] booting restored account '
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

  Future<void> setSelfProfileNickname(String nickname) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_self_profile',
      <String, Object?>{'nickname': nickname},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_set_self_profile failed: ${json['error']} '
        '(detail=${json['detail']})',
      );
    }
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
      final friend = await findFriend(userId);
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

  /// Polls dumpState every 1s up to [timeoutSecs] until the friend matched by
  /// [userId]'s public key has nickName == [expectedNickName]. Returns true on
  /// match, false on timeout.
  Future<bool> waitForFriendNickName({
    required String userId,
    required String expectedNickName,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    String? lastObserved;
    while (DateTime.now().isBefore(deadline)) {
      final friend = await findFriend(userId);
      final nick = friend?['nickName']?.toString();
      if (nick != lastObserved) {
        print('[fixture-c-self-profile][$name] friend nickName="$nick"');
        lastObserved = nick;
      }
      if (nick == expectedNickName) {
        return true;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  Future<String> describeFriend(String userId) async {
    final friend = await findFriend(userId);
    return friend?.toString() ?? '<not in friend list>';
  }

  Future<String> describeFriends() async {
    final state = await dumpState();
    final friends = (state['friends'] as List?) ?? const <dynamic>[];
    return friends.toString();
  }

  Future<Map<String, dynamic>?> findFriend(String userId) async {
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
