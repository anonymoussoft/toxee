// End-to-end driver for the S63 "read-receipts" L3 scenario.
//
// This validates the read-receipt MECHANISM end-to-end via the auto-'received'
// DELIVERY receipt: when B receives an inbound C2C message it automatically
// calls FfiChatService._sendReceipt(from, msgID, 'received'), which sends a
// 'receipt' custom message back to A. A's poll loop parses it and calls
// _handleReceipt(...), which flips the matching self-sent message's
// isReceived=true. The 'read' variant (isRead) fires only when the recipient
// EXPLICITLY marks-read (markMessageAsRead), which is exercised on conversation
// open — that path is NOT asserted here; this gate covers the delivery-receipt
// round-trip, which is sufficient to prove the receipt plumbing is live.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (when no manifest is given) already booted.
//
// Sequence:
//   1. Connect A and B; ensureReady both; waitForConnected; waitForFriendOnline;
//      resolve toxA/toxB via currentAccountToxId.
//   2. Clear both C2C histories to establish a clean baseline.
//   3. Generate a per-run nonce; A sends "S63 receipt <nonce>" to B.
//   4. PRIMARY (A1): poll A's conversation with B up to 90s until A's sent
//      message (match by text AND isSelf==true) has isReceived==true.
//   5. Return 0 (PASS) / 1 (drive error) / 64 (usage error).
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_receipt.dart \
//       <ws_uri_A> <ws_uri_B> [--fixture-manifest path]

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
      'usage: drive_fixture_c_receipt.dart <ws_uri_A> <ws_uri_B> '
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
      print('[fixture-c-receipt] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-receipt] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    // 2. Clean baseline.
    await a.clearHistory(toxB);
    await b.clearHistory(toxA);

    // 3. A sends the nonce text to B.
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final text = 'S63 receipt $nonce';
    print('[fixture-c-receipt] nonce=$nonce sending "$text" A->B');
    await a.sendText(toxB, text);

    // Capture the sent message's msgID from A's own conversation (the
    // isSelf==true entry with that text). Retried briefly: appendHistory
    // debounces ~200ms, so the just-sent message may not be in dumpState yet.
    final sent = await a.waitForSelfMessage(
      conversationId: toxB,
      text: text,
      timeoutSecs: 30,
    );
    final sentMsgId = sent['msgID']?.toString() ?? '';
    print('[fixture-c-receipt] A sent msgID=$sentMsgId');

    // 4. PRIMARY (A1): poll A's conversation with B until the sent message has
    // isReceived==true (B auto-sent a 'received' receipt that A processed).
    final received = await a.pollForReceived(
      conversationId: toxB,
      text: text,
      timeoutSecs: 90,
    );
    if (received == null) {
      // Timeout: dump the sent message's fields for diagnosis.
      final latest = await a.findSelfMessage(conversationId: toxB, text: text);
      throw _DriveError(
        'A1 received-receipt: A.sent message did not flip isReceived=true '
        'within 90s; '
        'msgID=${latest?['msgID']} isSelf=${latest?['isSelf']} '
        'text=${latest?['text']} isReceived=${latest?['isReceived']} '
        'isRead=${latest?['isRead']}',
      );
    }
    print(
      '[fixture-c-receipt] PASS A1 received-receipt: A.sent message '
      'isReceived=true (msgID=${received['msgID']} isRead=${received['isRead']})',
    );

    print('[fixture-c-receipt] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-receipt] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

List<Map<String, dynamic>> _messagesOf(Map<String, dynamic> state) {
  final raw = (state['messages'] as List?) ?? const <dynamic>[];
  return <Map<String, dynamic>>[
    for (final m in raw)
      if (m is Map) Map<String, dynamic>.from(m),
  ];
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
      print('[fixture-c-receipt][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-receipt][$name] booting restored account '
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

  /// Returns the isSelf==true message matching [text], or null if absent.
  Future<Map<String, dynamic>?> findSelfMessage({
    required String conversationId,
    required String text,
  }) async {
    final state = await dumpState(conversationId: conversationId);
    for (final m in _messagesOf(state)) {
      if (m['isSelf'] == true && m['text']?.toString() == text) {
        return m;
      }
    }
    return null;
  }

  /// Polls until the isSelf==true message matching [text] appears, returning it.
  Future<Map<String, dynamic>> waitForSelfMessage({
    required String conversationId,
    required String text,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final m = await findSelfMessage(conversationId: conversationId, text: text);
      if (m != null) return m;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] self-sent message "$text" never appeared in conversation '
      '${conversationId.substring(0, 16)}',
    );
  }

  /// Polls until the isSelf==true message matching [text] has
  /// isReceived==true, returning it. Returns null on timeout.
  Future<Map<String, dynamic>?> pollForReceived({
    required String conversationId,
    required String text,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final m = await findSelfMessage(conversationId: conversationId, text: text);
      if (m != null && m['isReceived'] == true) {
        return m;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return null;
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
