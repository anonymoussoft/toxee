// End-to-end driver for the S52 "self avatar change propagates to a friend"
// L3 scenario (two-process / paired pair).
//
// This asserts the kind-1 (TOX_FILE_KIND_AVATAR) file transfer reached B and
// set the FRIEND avatar PATH on B's friend-list entry for A — that is the
// propagation contract this gate verifies. Image-validity / visual repaint is
// explicitly OUT OF SCOPE: the avatar content sent here is arbitrary bytes
// (a per-run unique marker chosen only to beat the avatar hash-gate, so the
// transfer actually fires instead of being deduped).
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends. A
// changes its OWN avatar via l3_set_self_profile(avatarContent: ...) — the app
// writes a sandbox-safe temp source for the inline bytes and sends it as a
// kind-1 avatar file. The paired friend B observes the new stored avatarPath on
// its friend-list entry for A once the inbound transfer completes.
//
// Sequence:
//   1. Connect A and B; ensureReady (boot restored accounts); waitForConnected
//      both; resolve toxA/toxB via currentAccountToxId.
//   2. waitForFriendOnline both directions (A sees B, B sees A) so the kind-1
//      file transfer can ride a live connection.
//   3. Baseline: B's friend entry for A (matched by public key) — record its
//      current avatarPath ("before", may be null/empty); FAIL if A is not in
//      B's friend list.
//   4. Build a per-run nonce; on A call
//      l3_set_self_profile(avatarContent: 'S52-avatar-<nonce>'); assert
//      {ok:true} and 'avatar' in changed.
//   5. PRIMARY: poll B every 2s up to 180s (kind-1 file transfer over DHT is
//      slow) until A's friend entry has a NON-EMPTY avatarPath that DIFFERS
//      from the baseline (or simply non-empty if baseline was empty). On
//      timeout, print A's friend entry from B's last snapshot + before and
//      throw.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_avatar.dart \
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
      'usage: drive_fixture_c_avatar.dart <ws_uri_A> <ws_uri_B> '
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
      print('[fixture-c-avatar] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-avatar] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    // kind-1 avatar transfer only rides a live connection — wait both ways.
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
    final beforeAvatar = beforeFriend['avatarPath']?.toString() ?? '';
    print('[fixture-c-avatar] baseline B sees A avatarPath="$beforeAvatar"');

    // 4. Nonce-based unique avatar content; mutate A's own profile. The unique
    // value beats the avatar hash-gate so the kind-1 transfer actually fires.
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final avatarContent = 'S52-avatar-$nonce';
    print('[fixture-c-avatar] setting A avatar -> "$avatarContent"');
    await a.setSelfProfileAvatar(avatarContent);

    // 5. PRIMARY: poll B until its friend entry for A reflects a new stored
    // avatar path. kind-1 file transfer over DHT is slow — allow 180s @ 2s.
    final observed = await b.waitForFriendAvatarPath(
      userId: toxA,
      baselineAvatarPath: beforeAvatar,
      timeoutSecs: 180,
      intervalSecs: 2,
    );
    if (observed == null) {
      final lastFriend = await b.describeFriend(toxA);
      throw _DriveError(
        'B never observed a new avatar path for A; '
        'before="$beforeAvatar"; '
        'last A friend entry from B=$lastFriend',
      );
    }

    print('[fixture-c-avatar] PASS (B observed A avatar path=$observed)');
    print('[fixture-c-avatar] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-avatar] ERROR: ${e.message}');
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
      print('[fixture-c-avatar][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-avatar][$name] booting restored account '
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

  /// Sets A's OWN avatar from inline [avatarContent] bytes. The app writes a
  /// sandbox-safe temp source for the content and sends it as a kind-1 avatar
  /// file. Asserts {ok:true} and that 'avatar' is reported in `changed`.
  Future<void> setSelfProfileAvatar(String avatarContent) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_self_profile',
      <String, Object?>{'avatarContent': avatarContent},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_set_self_profile failed: ${json['error']} '
        '(detail=${json['detail']})',
      );
    }
    final changed = (json['changed'] as List?) ?? const <dynamic>[];
    final changedNames = changed.map((e) => e.toString()).toList();
    if (!changedNames.contains('avatar')) {
      throw _DriveError(
        '[$name] l3_set_self_profile did not report avatar changed: '
        'changed=$changedNames',
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

  /// Polls dumpState every [intervalSecs] up to [timeoutSecs] until the friend
  /// matched by [userId]'s public key has a NON-EMPTY avatarPath that differs
  /// from [baselineAvatarPath] (or simply non-empty when the baseline was
  /// empty). Returns the observed avatar path on success, or null on timeout.
  Future<String?> waitForFriendAvatarPath({
    required String userId,
    required String baselineAvatarPath,
    required int timeoutSecs,
    required int intervalSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    String? lastObserved;
    while (DateTime.now().isBefore(deadline)) {
      final friend = await findFriend(userId);
      final path = friend?['avatarPath']?.toString() ?? '';
      if (path != lastObserved) {
        print('[fixture-c-avatar][$name] friend avatarPath="$path"');
        lastObserved = path;
      }
      if (path.isNotEmpty && path != baselineAvatarPath) {
        return path;
      }
      await Future<void>.delayed(Duration(seconds: intervalSecs));
    }
    return null;
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
