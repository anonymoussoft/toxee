// End-to-end driver for the S29 "cross-process BLOCK enforcement" L3 scenario.
//
// S29 cross-process + live-validation OWED.
//
// The hermetic echo gate (tool/mcp_test/scenarios/l3_block_toggle.json) already
// proves block enforcement against the in-process echo peer. THIS gate proves it
// across TWO REAL toxee instances on the paired_for_e2e base, where A and B are
// ALREADY friends. It distinguishes "block dropped the message" from "B's
// messages never arrive at all" by unblocking and requiring delivery to resume.
//
// Block is a receive-side drop: a blocked sender's inbound C2C messages are
// suppressed before history (no non-self message lands), while the sender's own
// outbound send still goes out (isSelf is never filtered). So the assertion is
// made on the RECEIVER (A) side: after A blocks B, B's text must NOT appear as a
// non-self message in A's C2C(toxB) history.
//
// Sequence:
//   1. Connect A and B; ensureReady both (boots restored accounts).
//      waitForConnected; waitForFriendOnline both directions; resolve toxA/toxB.
//   2. A blocks B (l3_set_blocked blocked:true); assert A.blockedUsers ∋ B (pk).
//   3. B sends a unique-nonce text "xblk-<nonce>-1" to A.
//   4. Wait a bounded window (15s); ASSERT A's C2C(toxB) has NO non-self message
//      carrying that nonce (the block dropped it).
//   5. A unblocks B (l3_set_blocked blocked:false); assert A.blockedUsers ∌ B.
//   6. B sends a SECOND nonce text "xblk-<nonce>-2"; A MUST receive it as a
//      non-self message (proves unblock restores delivery). If this NEVER
//      arrives, that is a CONNECTIVITY failure, not block enforcement — surfaced
//      distinctly so a flake here is not misread as "block works".
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_block.dart \
//       <ws_uri_A> <ws_uri_B> [--block-window-secs 15] --fixture-manifest path

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
  // The negative window: how long to wait for the BLOCKED inbound message to
  // (not) arrive before asserting absence. Generous default so a slow DHT route
  // doesn't make the negative assertion pass for the wrong reason.
  var blockWindowSecs = 15;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      fixtureManifestPath = args[++i];
    } else if (arg == '--block-window-secs') {
      if (i + 1 >= args.length) {
        print('usage: --block-window-secs requires an integer');
        return 64;
      }
      final parsed = int.tryParse(args[++i]);
      if (parsed == null || parsed < 1) {
        print('usage: --block-window-secs requires a positive integer');
        return 64;
      }
      blockWindowSecs = parsed;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_block.dart <ws_uri_A> <ws_uri_B> '
      '[--block-window-secs 15] '
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
      print('[fixture-c-block] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-block] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final blockedText = 'xblk-$nonce-1';
    final unblockedText = 'xblk-$nonce-2';
    print('[fixture-c-block] nonce=$nonce blockWindowSecs=$blockWindowSecs');

    // 2. A blocks B; assert the live in-memory block set on A contains B.
    await a.setBlocked(userId: toxB, blocked: true);
    await a.waitForBlocked(peerId: toxB, present: true, timeoutSecs: 15);
    print('[fixture-c-block] A blocked B (A.blockedUsers ∋ B)');

    // 3. B sends the FIRST (blocked) nonce text to A.
    await b.sendText(toxA, blockedText);
    print('[fixture-c-block] B -> A (blocked) "$blockedText" issued');

    // 4. Bounded negative window: the inbound copy must NOT land on A. Poll for
    //    the window so the "absent" verdict isn't reached prematurely, then
    //    assert no non-self message carries the nonce in A's C2C(toxB).
    await a.assertInboundAbsent(
      conversationId: toxB,
      text: blockedText,
      windowSecs: blockWindowSecs,
    );
    print(
      '[fixture-c-block] PASS block-enforced: "$blockedText" never landed on A '
      'within ${blockWindowSecs}s',
    );

    // 5. A unblocks B; assert the block set on A no longer contains B.
    await a.setBlocked(userId: toxB, blocked: false);
    await a.waitForBlocked(peerId: toxB, present: false, timeoutSecs: 15);
    print('[fixture-c-block] A unblocked B (A.blockedUsers ∌ B)');

    // 6. B sends the SECOND (unblocked) nonce text; A MUST receive it. Failure
    //    here means the underlying C2C route is broken (CONNECTIVITY), not that
    //    block enforcement is working — surface that distinctly so a flake is
    //    never misread as a passing block.
    await b.sendText(toxA, unblockedText);
    print('[fixture-c-block] B -> A (unblocked) "$unblockedText" issued');
    final delivered = await a.waitForInboundText(
      conversationId: toxB,
      text: unblockedText,
      timeoutSecs: 90,
    );
    if (!delivered) {
      throw _DriveError(
        'CONNECTIVITY: the post-unblock control message "$unblockedText" never '
        'reached A — the C2C route is broken, so the earlier negative result '
        'does NOT prove block enforcement. Investigate two-process peer '
        'connectivity, not the block path.',
      );
    }
    print(
      '[fixture-c-block] PASS unblock-restores-delivery: "$unblockedText" '
      'received on A',
    );

    print('[fixture-c-block] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-block] ERROR: ${e.message}');
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
      'ext.mcp.toolkit.l3_set_blocked',
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
      print('[fixture-c-block][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-block][$name] booting restored account '
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

  // S29: block or unblock a peer via l3_set_blocked. Fails loudly if the SDK
  // path refuses (e.g. non-test account) so a refusal is never mistaken for an
  // enforced block.
  Future<void> setBlocked({
    required String userId,
    required bool blocked,
  }) async {
    final resp = await _call('ext.mcp.toolkit.l3_set_blocked', <String, Object?>{
      'userId': userId,
      'blocked': blocked,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_set_blocked(blocked=$blocked) failed: '
        'error=${json['error']} detail=${json['detail']}',
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

  // Poll l3_dump_state.blockedUsers until the peer's public key is present
  // (present:true) or gone (present:false). blockedUsers holds normalized Tox
  // ids; match by the 64-char public-key prefix so id-format differences (full
  // Tox ID vs bare pubkey) don't break the check.
  Future<void> waitForBlocked({
    required String peerId,
    required bool present,
    required int timeoutSecs,
  }) async {
    final wantPk = _toxPublicKey(peerId);
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      if (_blockedContains(await dumpState(), wantPk) == present) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final state = await dumpState();
    throw _DriveError(
      '[$name] blockedUsers ${present ? 'did not contain' : 'still contained'} '
      '${peerId.substring(0, 16)} within ${timeoutSecs}s; '
      'blockedUsers=${state['blockedUsers']}',
    );
  }

  bool _blockedContains(Map<String, dynamic> state, String wantPk) {
    final blocked = (state['blockedUsers'] as List?) ?? const <dynamic>[];
    for (final entry in blocked) {
      if (_toxPublicKey(entry?.toString() ?? '') == wantPk) return true;
    }
    return false;
  }

  // Negative assertion: poll the conversation for [windowSecs] and FAIL if a
  // NON-SELF (inbound) message carrying [text] ever appears. The block must drop
  // it before history, so no such message may land.
  Future<void> assertInboundAbsent({
    required String conversationId,
    required String text,
    required int windowSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: windowSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(conversationId: conversationId);
      for (final m in _messagesOf(state)) {
        if (m['text']?.toString() == text && m['isSelf'] == false) {
          _printMessageSummary(_messagesOf(state));
          throw _DriveError(
            '[$name] BLOCK NOT ENFORCED: inbound "$text" landed on the '
            'receiver side of ${conversationId.substring(0, 16)} despite the '
            'peer being blocked',
          );
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
  }

  // Positive wait: returns true once a NON-SELF (inbound) message carrying
  // [text] appears in the conversation, false if the timeout elapses first.
  Future<bool> waitForInboundText({
    required String conversationId,
    required String text,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(conversationId: conversationId);
      for (final m in _messagesOf(state)) {
        if (m['text']?.toString() == text && m['isSelf'] == false) {
          return true;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    return false;
  }

  void _printMessageSummary(List<Map<String, dynamic>> messages) {
    print('[fixture-c-block][$name] last ${messages.length} messages:');
    for (final m in messages) {
      print(
        '  msgID=${m['msgID']} isSelf=${m['isSelf']} text=${m['text']}',
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
