// End-to-end driver for the S33 "JOIN a group by chat-id (two processes)" L3
// scenario.
//
// LIVE VALIDATION OWED: this gate has NOT been run live yet. The residual is
// NGC two-process peer connectivity on the same host (a join can succeed at the
// FFI layer yet the joiner never observes the group as connected) — see
// `s37_kick_ngc_peer_connectivity_blocker` and the S34 driver's lag notes. Run
// `run_fixture_c_join.sh` against a built `libtim2tox_ffi` to validate.
//
// This is a SUBSET of drive_fixture_c_group.dart (S34): it does the SAME paired
// boot + full-mesh bootstrap + A create + B join-by-chat-id, then STOPS at the
// join assertion. It deliberately drops the A<->B group-message roundtrip (that
// is S34's job) — S33 only proves B can JOIN a group it was given the chat-id
// for.
//
// l3_create_group returns BOTH a LOCAL group id (e.g. "tox_1", which the creator
// keys its own history under) AND a separate 64-char hex `chatId` (the joinable
// public group id). B joins by that chat-id; `FfiChatService.joinGroup(chatId)`
// adds the chat-id VERBATIM to `_knownGroups` on success, so B keys `knownGroups`
// by the chat-id it joined with (NOT a derived local id). The S33 assertion
// matches B's `l3_dump_state.knownGroups` against that chat-id (exact, or a
// prefix — native id bookkeeping could in principle truncate/normalize it).
//
// Sequence:
//   1. Connect A and B; ensureReady both; resolve toxA/toxB via
//      currentAccountToxId; wait connected + friend-online both directions.
//   2. A: l3_create_group(name) -> capture LOCAL groupIdA AND the 64-hex chatId.
//      Validate the chatId is 64-hex (it is what B joins with).
//   3. B: join the chat-id, retrying ~6x (3s spacing) for DHT/create lag; sleep
//      ~3s after join for NGC connect.
//   4. ASSERT (S33 contract): B's l3_dump_state.knownGroups contains the joined
//      group id (match the chatId exactly or by prefix). Fail LOUDLY — dumping
//      B's knownGroups — if B never joins.
//   5. Return 0 pass / 1 fail / 64 usage.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_join.dart \
//       <ws_uri_A> <ws_uri_B> --fixture-manifest path

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
      'usage: drive_fixture_c_join.dart <ws_uri_A> <ws_uri_B> '
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
    if (fixture != null) {
      await a.ensureReady(fixture: fixture.a);
      await b.ensureReady(fixture: fixture.b);
    } else {
      print('[fixture-c-join] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // Full-mesh loopback bootstrap so A and B discover each other as NGC peers
    // (same-host public-DHT group discovery is slow/flaky) before the group
    // create/join.
    await wireFullMeshBootstrap([
      BootstrapTarget('A', a.vm, a.isolateId),
      BootstrapTarget('B', b.vm, b.isolateId),
    ]);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-join] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    // 2. A creates the public NGC group. l3_create_group returns BOTH a LOCAL
    // group id (groupIdA, e.g. "tox_1") AND the joinable 64-char hex chatId
    // (what B joins with). Validate the chatId shape.
    final created = await a.createGroup(name: 'l3_s33_$nonce');
    final groupIdA = created.groupId;
    final chatId = created.chatId;
    if (groupIdA.isEmpty) {
      throw _DriveError(
        'create_group returned an empty local groupId '
        '(chatId="$chatId" len=${chatId.length})',
      );
    }
    if (!_isChatId(chatId)) {
      throw _DriveError(
        'create_group chatId is not 64-char hex (cannot be joined): '
        'groupId="$groupIdA" (len=${groupIdA.length}) '
        'chatId="$chatId" (len=${chatId.length}). Expected a 64-char hex NGC '
        'chat-id so B can l3_join_group it.',
      );
    }
    print(
      '[fixture-c-join] created group: localGroupId="$groupIdA" '
      'chatId=${chatId.substring(0, 16)}... (64-hex)',
    );

    // 3. B joins by chat-id; DHT group discovery / create-lag can delay it, so
    // retry. After a successful join, let NGC connect settle.
    await b.joinGroupWithRetry(chatId, attempts: 6, spacingMs: 3000);
    print('[fixture-c-join] B joined group; waiting ~3s for NGC connect');
    await Future<void>.delayed(const Duration(seconds: 3));

    // 4. ASSERT (S33 contract): B keys knownGroups by the chat-id it joined
    // with (FfiChatService.joinGroup adds the argument verbatim). The join
    // call returning ok is not enough — confirm the joined id is actually
    // reflected in B's authoritative in-memory joined set. knownGroups can
    // settle a beat after the join, so poll briefly before failing loudly.
    final joinedKey = await b.waitForKnownGroup(chatId, timeoutSecs: 30);
    print('[fixture-c-join] PASS B joined (knownGroups key=$joinedKey)');

    print('[fixture-c-join] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-join] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

/// A 64-char hex string is the joinable NGC chat-id shape.
bool _isChatId(String id) {
  if (id.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(id);
}

/// True if `known` (a `knownGroups` entry) is the group B joined with: an exact
/// match on `chatId`, or a prefix relationship either way (native id bookkeeping
/// could truncate/normalize the 64-hex chat-id). Case-insensitive.
bool _matchesJoinedGroup(String known, String chatId) {
  final k = known.trim().toLowerCase();
  final c = chatId.trim().toLowerCase();
  if (k.isEmpty || c.isEmpty) return false;
  return k == c || k.startsWith(c) || c.startsWith(k);
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

/// The two ids l3_create_group returns: a LOCAL group id (creator's history
/// key) and the joinable 64-char hex chat-id.
class _CreatedGroup {
  _CreatedGroup({required this.groupId, required this.chatId});
  final String groupId;
  final String chatId;
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
      'ext.mcp.toolkit.l3_create_group',
      timeoutSecs: 60,
    );
    await d.waitForExtension('ext.mcp.toolkit.l3_join_group', timeoutSecs: 60);
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
      print('[fixture-c-join][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-join][$name] booting restored account '
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

  /// Create a PUBLIC NGC group; returns BOTH the LOCAL group id and the
  /// joinable 64-char hex chat-id.
  Future<_CreatedGroup> createGroup({String? name}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_create_group',
      name == null
          ? const <String, Object?>{}
          : <String, Object?>{'name': name},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_create_group failed: ${json['error']}');
    }
    final gid = (json['groupId']?.toString() ?? '').trim();
    final chatId = (json['chatId']?.toString() ?? '').trim();
    return _CreatedGroup(groupId: gid, chatId: chatId);
  }

  /// Join a public group by chat-id. NGC discovery can lag, so a join failure
  /// is retryable: try `attempts` times with `spacingMs` spacing.
  Future<void> joinGroupWithRetry(
    String groupId, {
    required int attempts,
    required int spacingMs,
  }) async {
    Object? lastErr;
    for (var i = 0; i < attempts; i++) {
      try {
        await joinGroup(groupId);
        return;
      } on _DriveError catch (e) {
        lastErr = e;
        print(
          '[fixture-c-join][$name] join attempt ${i + 1}/$attempts failed: '
          '${e.message}',
        );
        if (i < attempts - 1) {
          await Future<void>.delayed(Duration(milliseconds: spacingMs));
        }
      }
    }
    throw _DriveError(
      '[$name] l3_join_group failed after $attempts attempts: '
      '${lastErr is _DriveError ? lastErr.message : lastErr}',
    );
  }

  Future<void> joinGroup(String groupId) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_join_group',
      <String, Object?>{'groupId': groupId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('l3_join_group failed: ${json['error']}');
    }
  }

  /// Poll B's `knownGroups` (the authoritative in-memory joined set) for an
  /// entry that matches the joined `chatId` (exact or prefix). Returns the
  /// matching knownGroups key. On timeout, dump knownGroups and throw — the
  /// residual is NGC two-process connectivity (a join can return ok yet the
  /// group never settle into the joined set on the same host).
  Future<String> waitForKnownGroup(
    String chatId, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final known = await _knownGroups();
      for (final g in known) {
        if (_matchesJoinedGroup(g, chatId)) return g;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final known = await _knownGroups();
    throw _DriveError(
      '[$name] never joined group chatId=${chatId.substring(0, 16)}... within '
      '${timeoutSecs}s — knownGroups=$known (NGC two-process peer connectivity '
      'is the residual; a join can return ok yet never settle into the joined '
      'set on the same host)',
    );
  }

  Future<List<String>> _knownGroups() async {
    final state = await dumpState();
    final known = (state['knownGroups'] as List?) ?? const <dynamic>[];
    return [
      for (final g in known)
        if ((g?.toString().trim() ?? '').isNotEmpty) g.toString().trim(),
    ];
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
