// End-to-end driver for the S64 "concurrent send (two processes)" L3 scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (when no manifest is given) already booted. It stresses concurrency by
// interleaving message sends from both sides (A,B,A,B...) and then asserts that
// both conversations converge with no loss, no duplicate msgIDs, and per-stream
// timestamp ordering preserved.
//
// Sequence:
//   1. Connect A and B; resolve toxA/toxB via currentAccountToxId.
//   2. Generate a per-run nonce; build A-<nonce>-NNN / B-<nonce>-NNN texts.
//   3. Clear both C2C histories to establish a clean count baseline.
//   4. Interleave 2N sends (A then B per iteration).
//   5. Settle: poll until each side sees the peer's LAST message, then +1500ms.
//   6. Fetch final state and run assertions A1..A4.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_concurrent.dart \
//       <ws_uri_A> <ws_uri_B> [--n 10] [--fixture-manifest path]

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
  var n = 10;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      fixtureManifestPath = args[++i];
    } else if (arg == '--n') {
      if (i + 1 >= args.length) {
        print('usage: --n requires an integer');
        return 64;
      }
      final parsed = int.tryParse(args[++i]);
      if (parsed == null || parsed < 1) {
        print('usage: --n requires a positive integer');
        return 64;
      }
      n = parsed;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_concurrent.dart <ws_uri_A> <ws_uri_B> '
      '[--n 10] [--fixture-manifest path/to/paired_for_e2e_manifest.json]',
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
      print('[fixture-c-concurrent] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-concurrent] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final aTexts = <String>[
      for (var i = 1; i <= n; i++) 'A-$nonce-${_pad3(i)}',
    ];
    final bTexts = <String>[
      for (var i = 1; i <= n; i++) 'B-$nonce-${_pad3(i)}',
    ];
    print('[fixture-c-concurrent] nonce=$nonce n=$n (2N=${2 * n} sends)');

    // 3. Clean count baseline.
    await a.clearHistory(toxB);
    await b.clearHistory(toxA);

    // 4. Interleave the sends: A,B,A,B,...
    for (var i = 0; i < n; i++) {
      await a.sendText(toxB, aTexts[i]);
      await b.sendText(toxA, bTexts[i]);
    }
    print('[fixture-c-concurrent] all ${2 * n} sends issued');

    // 5. Settle: wait for the peer's LAST message on each side.
    final lastFromA = aTexts.last; // expected on B
    final lastFromB = bTexts.last; // expected on A
    await a.waitForText(
      conversationId: toxB,
      text: lastFromB,
      timeoutSecs: 90,
    );
    await b.waitForText(
      conversationId: toxA,
      text: lastFromA,
      timeoutSecs: 90,
    );
    // appendHistory debounces 200ms; allow late deliveries.
    await Future<void>.delayed(const Duration(milliseconds: 1500));

    // 6. Final state.
    final aState = await a.dumpState(conversationId: toxB);
    final bState = await b.dumpState(conversationId: toxA);

    final aMessages = _messagesOf(aState);
    final bMessages = _messagesOf(bState);
    final aCount = _countOf(aState);
    final bCount = _countOf(bState);

    final allTexts = <String>{...aTexts, ...bTexts};
    _runAssertions(
      n: n,
      nonce: nonce,
      allTexts: allTexts,
      aTexts: aTexts,
      bTexts: bTexts,
      aMessages: aMessages,
      bMessages: bMessages,
      aCount: aCount,
      bCount: bCount,
    );

    print('[fixture-c-concurrent] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-concurrent] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

String _pad3(int i) => i.toString().padLeft(3, '0');

List<Map<String, dynamic>> _messagesOf(Map<String, dynamic> state) {
  final raw = (state['messages'] as List?) ?? const <dynamic>[];
  return <Map<String, dynamic>>[
    for (final m in raw)
      if (m is Map) Map<String, dynamic>.from(m),
  ];
}

int _countOf(Map<String, dynamic> state) {
  final c = state['messageCount'];
  if (c is int) return c;
  if (c is num) return c.toInt();
  return int.tryParse(c?.toString() ?? '') ?? -1;
}

void _runAssertions({
  required int n,
  required String nonce,
  required Set<String> allTexts,
  required List<String> aTexts,
  required List<String> bTexts,
  required List<Map<String, dynamic>> aMessages,
  required List<Map<String, dynamic>> bMessages,
  required int aCount,
  required int bCount,
}) {
  final expectedCount = 2 * n;

  // A1: count == 2N on both sides.
  if (aCount != expectedCount || bCount != expectedCount) {
    throw _DriveError(
      'A1 count: expected $expectedCount on both sides; '
      'got A.messageCount=$aCount B.messageCount=$bCount',
    );
  }
  print('[fixture-c-concurrent] PASS A1 count: both sides == $expectedCount');

  // A2: no loss — every expected text present on both sides.
  final aTextSet = <String>{
    for (final m in aMessages) (m['text']?.toString() ?? ''),
  };
  final bTextSet = <String>{
    for (final m in bMessages) (m['text']?.toString() ?? ''),
  };
  final missingOnA = allTexts.where((t) => !aTextSet.contains(t)).toList()
    ..sort();
  final missingOnB = allTexts.where((t) => !bTextSet.contains(t)).toList()
    ..sort();
  if (missingOnA.isNotEmpty || missingOnB.isNotEmpty) {
    throw _DriveError(
      'A2 no loss: missing on A=$missingOnA missing on B=$missingOnB',
    );
  }
  print('[fixture-c-concurrent] PASS A2 no loss: all $expectedCount texts on '
      'both sides');

  // A3: no duplicate msgIDs (and every message has a real msgID).
  _assertNoDup('A', aMessages);
  _assertNoDup('B', bMessages);
  print('[fixture-c-concurrent] PASS A3 no dup: msgIDs unique on both sides');

  // A4: per-stream ordering — A-stream and B-stream each ascending in both
  // msg-number order and timestamp order, on each side.
  _assertOrdering('A', side: 'A', messages: aMessages, nonce: nonce);
  _assertOrdering('B', side: 'A', messages: aMessages, nonce: nonce);
  _assertOrdering('A', side: 'B', messages: bMessages, nonce: nonce);
  _assertOrdering('B', side: 'B', messages: bMessages, nonce: nonce);
  print('[fixture-c-concurrent] PASS A4 ordering: A-/B- streams ascending on '
      'both sides');
}

void _assertNoDup(String side, List<Map<String, dynamic>> messages) {
  final seen = <String>{};
  for (final m in messages) {
    final raw = m['msgID']?.toString().trim() ?? '';
    if (raw.isEmpty) {
      throw _DriveError(
        'A3 no dup: $side has a message lacking a real msgID '
        '(dedup unverifiable): text=${m['text']}',
      );
    }
    if (!seen.add(raw)) {
      throw _DriveError(
        'A3 no dup: $side has duplicate msgID "$raw" (text=${m['text']})',
      );
    }
  }
}

// `prefix` is the stream prefix ('A' or 'B'); `side` is the conversation owner
// (for error messages only).
void _assertOrdering(
  String prefix, {
  required String side,
  required List<Map<String, dynamic>> messages,
  required String nonce,
}) {
  final streamPrefix = '$prefix-$nonce-';
  // Preserve the dumpState message order while filtering to this stream.
  final stream = <Map<String, dynamic>>[
    for (final m in messages)
      if ((m['text']?.toString() ?? '').startsWith(streamPrefix)) m,
  ];

  // Verify the filtered order is the expected 001->0NN msg-number order AND
  // timestamps are ascending.
  DateTime? prevTs;
  int? prevNum;
  for (final m in stream) {
    final text = m['text']?.toString() ?? '';
    final num = _msgNumber(text, streamPrefix);
    if (num == null) {
      throw _DriveError(
        'A4 ordering: on $side, $prefix-stream text "$text" is unparseable',
      );
    }
    if (prevNum != null && num <= prevNum) {
      throw _DriveError(
        'A4 ordering: on $side, $prefix-stream not in ascending msg-number '
        'order (saw #$num after #$prevNum)',
      );
    }
    final tsRaw = m['timestamp']?.toString() ?? '';
    final ts = DateTime.tryParse(tsRaw);
    if (ts == null) {
      throw _DriveError(
        'A4 ordering: on $side, $prefix-stream message "$text" has '
        'unparseable timestamp "$tsRaw"',
      );
    }
    if (prevTs != null && ts.isBefore(prevTs)) {
      throw _DriveError(
        'A4 ordering: on $side, $prefix-stream timestamps not ascending '
        '($ts before $prevTs at "$text")',
      );
    }
    prevTs = ts;
    prevNum = num;
  }
}

int? _msgNumber(String text, String streamPrefix) {
  if (!text.startsWith(streamPrefix)) return null;
  return int.tryParse(text.substring(streamPrefix.length));
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
    await d.waitForExtension('ext.mcp.toolkit.l3_send_text', timeoutSecs: 60);
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_clear_history',
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
      print('[fixture-c-concurrent][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-concurrent][$name] booting restored account '
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

  Future<void> clearHistory(String userId) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_clear_history',
      <String, Object?>{'userId': userId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_clear_history failed: ${json['error']}');
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

  Future<void> waitForText({
    required String conversationId,
    required String text,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(conversationId: conversationId);
      final msgs = (state['messages'] as List?) ?? const <dynamic>[];
      for (final m in msgs) {
        if (m is Map && m['text']?.toString() == text) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] message "$text" in conversation '
      '${conversationId.substring(0, 16)} timed out',
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
