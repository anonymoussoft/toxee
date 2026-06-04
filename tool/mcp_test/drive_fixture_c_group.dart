// End-to-end driver for the S34 "group message (two processes)" L3 scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (after ensureReady) booted. A creates a PUBLIC NGC group; l3_create_group
// returns BOTH a LOCAL group id (e.g. "tox_1", used by the creator to key its
// own history) AND a separate 64-char hex `chatId` (the joinable public group
// id). B joins by that chat-id; then a group text roundtrips A->B and B->A.
//
// Cross-side group-id keying is ambiguous: the creator keys history by its
// LOCAL id, the joiner by the chat-id, and the native layer may use yet other
// ids. So READS never assume a single key — pollGroupInbound recomputes the
// SET of candidate group ids per side (from `knownGroups` + group-typed
// `conversations`) and scans the history under EVERY candidate. NGC group
// discovery / connect can lag, so joins retry and each roundtrip send is
// re-issued once before failing.
//
// Sequence:
//   1. Connect A and B; ensureReady both; resolve toxA/toxB via
//      currentAccountToxId; wait connected + friend-online both directions.
//   2. A: l3_create_group(name) -> capture LOCAL groupIdA AND the 64-hex chatId.
//      Validate the chatId is 64-hex (it is what B joins with).
//   3. B: join the chat-id, retrying ~6x (3s spacing) for DHT lag; sleep ~3s
//      after join for NGC connect.
//   4. ROUNDTRIP A->B: A sends via groupIdA; poll B's group history across all
//      candidate keys (90s, re-send once from A, then poll again) for an
//      inbound (isSelf==false) message with the exact text.
//   5. ROUNDTRIP B->A: B sends via the chat-id it joined with; poll A's group
//      history across all candidate keys (90s, re-send once) likewise.
//   6. Return 0 all-pass / 1 fail / 64 usage.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_group.dart \
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
      'usage: drive_fixture_c_group.dart <ws_uri_A> <ws_uri_B> '
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
      print('[fixture-c-group] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // Full-mesh loopback bootstrap so A and B discover each other as NGC peers
    // (same-host public-DHT group discovery is slow/flaky) before the group
    // create/join/roundtrip.
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
      '[fixture-c-group] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    // 2. A creates the public NGC group. l3_create_group returns BOTH a LOCAL
    // group id (groupIdA, e.g. "tox_1" — what A uses to send) AND the joinable
    // 64-char hex chatId (what B joins with). Validate the chatId shape.
    final created = await a.createGroup(name: 'l3_s34_$nonce');
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
      '[fixture-c-group] created group: localGroupId="$groupIdA" '
      'chatId=${chatId.substring(0, 16)}... (64-hex)',
    );

    // 3. B joins by chat-id; DHT group discovery can lag, so retry. After a
    // successful join, let NGC connect settle before the first send.
    await b.joinGroupWithRetry(chatId, attempts: 6, spacingMs: 3000);
    print('[fixture-c-group] B joined group; waiting ~3s for NGC connect');
    await Future<void>.delayed(const Duration(seconds: 3));

    // 4. ROUNDTRIP A->B (first send doubles as the NGC-readiness probe). A
    // sends via its LOCAL group id; B reads across all candidate keys.
    final textAB = 'S34 A->B $nonce';
    final keyAB = await _roundtrip(
      sender: a,
      senderGroupId: groupIdA,
      observer: b,
      text: textAB,
      label: 'A1 A->B',
    );
    print('[fixture-c-group] PASS A1 A->B (key=$keyAB)');

    // 5. ROUNDTRIP B->A. B sends via the chat-id it joined with; A reads across
    // all candidate keys (which include A's local id).
    final textBA = 'S34 B->A $nonce';
    final keyBA = await _roundtrip(
      sender: b,
      senderGroupId: chatId,
      observer: a,
      text: textBA,
      label: 'A2 B->A',
    );
    print('[fixture-c-group] PASS A2 B->A (key=$keyBA)');

    print('[fixture-c-group] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-group] ERROR: ${e.message}');
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

/// Collect the SET of candidate group ids `driver` might key its group history
/// under: every entry of base-dump `knownGroups`, PLUS — for every
/// `conversations` entry of type 2 (group) — its conversationID with a leading
/// 'group_' stripped. Used so READS try ALL keys (creator keys by local id,
/// joiner by chat-id, native may use other ids).
Future<Set<String>> _groupCandidates(_PairDriver driver) async {
  final state = await driver.dumpState();
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

/// Poll `observer`'s group history for an inbound (isSelf==false) message with
/// the exact `text`, scanning across ALL candidate group keys (recomputed each
/// pass via [_groupCandidates]). Returns the candidate key that matched. On
/// timeout, dump the observer's knownGroups + each candidate's messages and
/// throw.
Future<String> _pollGroupInbound(
  _PairDriver observer, {
  required String text,
  required int timeoutSecs,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final candidates = await _groupCandidates(observer);
    for (final candidate in candidates) {
      final state = await observer.dumpState(
        conversationId: 'group_$candidate',
      );
      final msgs = (state['messages'] as List?) ?? const <dynamic>[];
      for (final m in msgs) {
        if (m is Map &&
            m['isSelf'] == false &&
            m['text']?.toString() == text) {
          return candidate;
        }
      }
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  // Timeout diagnostics: knownGroups + each candidate's compact messages.
  final base = await observer.dumpState();
  final known = (base['knownGroups'] as List?) ?? const <dynamic>[];
  print('[fixture-c-group][${observer.name}] timeout; knownGroups=$known');
  final candidates = await _groupCandidates(observer);
  for (final candidate in candidates) {
    final state = await observer.dumpState(conversationId: 'group_$candidate');
    final msgs = (state['messages'] as List?) ?? const <dynamic>[];
    final summary = <Map<String, Object?>>[
      for (final m in msgs)
        if (m is Map)
          {'msgID': m['msgID'], 'isSelf': m['isSelf'], 'text': m['text']},
    ];
    print(
      '[fixture-c-group][${observer.name}] candidate "$candidate" '
      'messages=$summary',
    );
  }
  throw _DriveError(
    'observer ${observer.name} never saw inbound group text "$text" within '
    '${timeoutSecs}s across candidates=$candidates',
  );
}

/// Send `text` from `sender` (via `senderGroupId`, an id that side actually
/// knows) to the group, then poll `observer`'s group history across all
/// candidate keys for an inbound message with that exact text. A group message
/// can drop before the peer fully syncs, so if the first 90s poll throws,
/// re-send once from the sender and poll again (another 90s) before failing.
/// Returns the candidate key on which the message was observed.
Future<String> _roundtrip({
  required _PairDriver sender,
  required String senderGroupId,
  required _PairDriver observer,
  required String text,
  required String label,
}) async {
  await sender.sendGroupText(senderGroupId, text);
  try {
    return await _pollGroupInbound(observer, text: text, timeoutSecs: 90);
  } on _DriveError {
    print('[fixture-c-group] $label not seen in 90s; re-sending once');
    await sender.sendGroupText(senderGroupId, text);
    return _pollGroupInbound(observer, text: text, timeoutSecs: 90);
  }
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
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_send_group_text',
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
      print('[fixture-c-group][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-group][$name] booting restored account '
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
          '[fixture-c-group][$name] join attempt ${i + 1}/$attempts failed: '
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

  /// Send a group text via a group id THIS side actually knows. Surfaces
  /// {ok:false,error,detail} send failures.
  Future<void> sendGroupText(String groupId, String text) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_send_group_text',
      <String, Object?>{'groupId': groupId, 'text': text},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_send_group_text failed: error=${json['error']} '
        'detail=${json['detail']}',
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
