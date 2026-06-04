// End-to-end driver for the S83 "mute a conversation -> inbound notification
// suppressed" L3 scenario (mute-STATE half).
//
// The OS-banner-absence proof (a log stream on UNUserNotificationCenter) is
// OS-gated and OUT OF SCOPE for this gate. What this DOES gate is that the mute
// STATE that `notification_message_listener._shouldSuppress` consumes — the
// UIKit conversation CACHE entry's `recvOpt` — is set correctly when a
// conversation is muted via `l3_set_c2c_recv_opt`. `_shouldSuppress` suppresses
// the banner exactly when `recvOpt != 0`, so asserting `recvOpt == 2` on the
// c2c conversation entry is the precise state precondition for suppression.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends with
// seeded history, so A's conversation list already contains a c2c conversation
// for B. All assertions are made on A; B is only booted to be a live friend.
//
// Sequence:
//   1. Connect A and B; ensureReady(fixture) both; waitForConnected; resolve
//      toxA/toxB via currentAccountToxId.
//   2. Find A's c2c conversation with B (type==1, conversationID minus the
//      leading `c2c_` matches toxB's public key); FAIL if none appears. Record
//      the baseline recvOpt (expect 0 / null).
//   3. MUTE: A.l3_set_c2c_recv_opt(userId: toxB, opt: '2'); assert ok==true AND
//      cacheMatched >= 1 (cacheMatched==0 means the cached conversation that
//      _shouldSuppress reads was NOT updated).
//   4. ASSERT: poll up to 15s until A's c2c_B entry has recvOpt == 2.
//   5. CLEANUP (finally): A.l3_set_c2c_recv_opt(userId: toxB, opt: '0') to
//      unmute; best-effort.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_mute.dart \
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
      'usage: drive_fixture_c_mute.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path/to/paired_for_e2e_manifest.json]',
    );
    return 64;
  }
  final fixture = fixtureManifestPath == null
      ? null
      : await _FixtureManifest.load(fixtureManifestPath);
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  // Resolved once A is ready; needed for best-effort cleanup in finally.
  String? toxB;
  try {
    if (fixture != null) {
      await a.ensureReady(fixture: fixture.a);
      await b.ensureReady(fixture: fixture.b);
    } else {
      print('[fixture-c-mute] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final resolvedToxB = await b.currentToxId();
    if (toxA.isEmpty || resolvedToxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$resolvedToxB');
    }
    toxB = resolvedToxB;
    print(
      '[fixture-c-mute] toxA=${toxA.substring(0, 16)}... '
      'toxB=${resolvedToxB.substring(0, 16)}...',
    );

    // 2. Find A's c2c conversation with B (the fixture seeds the history that
    // creates it). Poll up to 60s — the conversation list hydrates after login.
    final wantPk = _toxPublicKey(resolvedToxB);
    final baseline = await a.waitForC2cConversation(
      wantPk: wantPk,
      timeoutSecs: 60,
    );
    final baselineOpt = baseline['recvOpt'];
    print(
      '[fixture-c-mute] found c2c conversation ${baseline['conversationID']} '
      'baseline recvOpt=$baselineOpt',
    );

    // 3. MUTE.
    final muteResult = await a.setC2cRecvOpt(userId: resolvedToxB, opt: '2');
    if (muteResult['ok'] != true) {
      throw _DriveError(
        'l3_set_c2c_recv_opt(opt=2) failed: ${muteResult['error'] ?? muteResult}',
      );
    }
    final cacheMatched = _intOf(muteResult['cacheMatched']);
    if (cacheMatched < 1) {
      throw _DriveError(
        'mute did not update the cached conversation _shouldSuppress reads: '
        'cacheMatched=$cacheMatched (expected >= 1)',
      );
    }
    print(
      '[fixture-c-mute] muted toxB opt=2 ok=true cacheMatched=$cacheMatched',
    );

    // 4. ASSERT: poll until the c2c_B entry reflects recvOpt == 2.
    await a.waitForRecvOpt(wantPk: wantPk, expected: 2, timeoutSecs: 15);
    print(
      '[fixture-c-mute] PASS: c2c conversation recvOpt == 2 '
      '(recvOpt != 0 is exactly what _shouldSuppress suppresses on)',
    );

    print('[fixture-c-mute] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-mute] ERROR: ${e.message}');
    return 1;
  } finally {
    // 5. Best-effort unmute so reruns start from a clean baseline. Wrapped so a
    // failed cleanup never masks the real outcome.
    if (toxB != null) {
      try {
        await a.setC2cRecvOpt(userId: toxB, opt: '0');
        print('[fixture-c-mute] cleanup: unmuted toxB (opt=0)');
      } catch (e) {
        print('[fixture-c-mute] cleanup: unmute best-effort failed: $e');
      }
    }
    await a.dispose();
    await b.dispose();
  }
}

int _intOf(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v?.toString() ?? '') ?? -1;
}

int? _recvOptOf(Map<String, dynamic> conversation) {
  final v = conversation['recvOpt'];
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

List<Map<String, dynamic>> _conversationsOf(Map<String, dynamic> state) {
  final raw = (state['conversations'] as List?) ?? const <dynamic>[];
  return <Map<String, dynamic>>[
    for (final c in raw)
      if (c is Map) Map<String, dynamic>.from(c),
  ];
}

Map<String, dynamic>? _findC2c(
  List<Map<String, dynamic>> conversations,
  String wantPk,
) {
  for (final c in conversations) {
    if (_intOf(c['type']) != 1) continue;
    final cid = c['conversationID']?.toString() ?? '';
    final bare = cid.startsWith('c2c_') ? cid.substring(4) : cid;
    if (_toxPublicKey(bare) == wantPk) return c;
  }
  return null;
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
      'ext.mcp.toolkit.l3_set_c2c_recv_opt',
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

  Future<Map<String, dynamic>> setC2cRecvOpt({
    required String userId,
    required String opt,
  }) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_c2c_recv_opt',
      <String, Object?>{'userId': userId, 'opt': opt},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-mute][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-mute][$name] booting restored account '
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

  Future<Map<String, dynamic>> waitForC2cConversation({
    required String wantPk,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      final conv = _findC2c(_conversationsOf(state), wantPk);
      if (conv != null) return conv;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final state = await dumpState();
    throw _DriveError(
      '[$name] no c2c conversation for pubkey ${wantPk.substring(0, 16)} '
      'appeared within ${timeoutSecs}s (fixture should have seeded history); '
      'conversations=${_conversationsOf(state)}',
    );
  }

  Future<void> waitForRecvOpt({
    required String wantPk,
    required int expected,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      final conv = _findC2c(_conversationsOf(state), wantPk);
      if (conv != null && _recvOptOf(conv) == expected) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    final state = await dumpState();
    final conversations = _conversationsOf(state);
    final conv = _findC2c(conversations, wantPk);
    throw _DriveError(
      '[$name] c2c conversation recvOpt did not reach $expected within '
      '${timeoutSecs}s; entry=$conv; conversations=$conversations',
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
