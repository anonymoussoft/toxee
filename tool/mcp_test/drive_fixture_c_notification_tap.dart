// End-to-end driver for the S53 "tap a message notification → opens the
// conversation" L3 scenario — the ROUTING half only.
//
// The OS banner POST and the OS-level tap that produces it remain OS-gated and
// out of scope for this gate. What this DOES exercise is the wired in-app
// routing seam that the OS tap handler feeds:
//
//   NotificationService.onSelectStream
//     → NotificationMessageListener.onConversationTapped
//     → _routeToNotificationPayload
//     → _openChat
//     → UikitDataFacade.currentConversation (+ flip to the Chats tab)
//
// `l3_simulate_notification_tap {conversationId}` injects a tap payload onto the
// SAME onSelectStream the OS handler writes to, so the real routing runs.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends with
// seeded history, so a C2C conversation A↔B already exists in A's conversation
// list. All assertions are on A; B is connected only so we can read/boot toxB.
//
// IMPORTANT: notification routing sets `UikitDataFacade.currentConversation`,
// NOT `ffi.activePeerId` — so we assert on `l3_dump_state.currentConversation`.
// The expected conversationID is `c2c_<toxB's 64-hex public key>`; we do NOT
// assume hex case — we compare by stripping a leading `c2c_`/`group_` prefix and
// matching the Tox public key.
//
// Sequence:
//   1. Connect A and B; ensureReady(fixture) both; waitForConnected(60) both;
//      resolve toxA/toxB via currentAccountToxId.
//   2. BASELINE: read A.currentConversation and assert it does NOT already
//      resolve to toxB's pubkey (right after boot it should be null). If it
//      already equals the target, FAIL loudly (the tap cannot be proven to
//      cause the open).
//   3. INJECT: A.l3_simulate_notification_tap(conversationId: 'c2c_<toxB>');
//      assert {ok:true}.
//   4. POLL: A.currentConversation every 500ms up to 30s until its
//      conversationID (prefix-stripped, Tox-pubkey-matched) == toxB. PASS.
//   5. Return 0/1/64.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_notification_tap.dart \
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
      'usage: drive_fixture_c_notification_tap.dart <ws_uri_A> <ws_uri_B> '
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
      print('[fixture-c-notif-tap] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    final wantPk = _toxPublicKey(toxB);
    print(
      '[fixture-c-notif-tap] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}... target=c2c_$wantPk',
    );

    // 2. BASELINE: A's open conversation must NOT already be the target.
    final baseline = await a.currentConversation();
    final baselinePk = _conversationPublicKey(baseline);
    print(
      '[fixture-c-notif-tap] baseline currentConversation=${baseline ?? '<null>'}',
    );
    if (baselinePk != null && baselinePk == wantPk) {
      throw _DriveError(
        'BASELINE: A.currentConversation already resolves to toxB '
        '(conversationID=${baseline?['conversationID']}); the tap cannot be '
        'proven to cause the open. Expected null/other right after boot.',
      );
    }
    print('[fixture-c-notif-tap] PASS baseline: A is NOT already open on toxB');

    // 3. INJECT: drive the real in-app routing via onSelectStream.
    final tapResult = await a.simulateNotificationTap('c2c_$toxB');
    if (tapResult['ok'] != true) {
      throw _DriveError(
        'INJECT: l3_simulate_notification_tap returned ok!=true: $tapResult',
      );
    }
    print(
      '[fixture-c-notif-tap] PASS inject: tap accepted '
      '(payload=${tapResult['payload']})',
    );

    // 4. POLL: routing must flip currentConversation to toxB.
    final deadline = DateTime.now().add(const Duration(seconds: 30));
    Map<String, dynamic>? last;
    while (DateTime.now().isBefore(deadline)) {
      last = await a.currentConversation();
      if (_conversationPublicKey(last) == wantPk) {
        print(
          '[fixture-c-notif-tap] PASS routing: currentConversation flipped to '
          'toxB (conversationID=${last?['conversationID']})',
        );
        print('[fixture-c-notif-tap] PASS');
        return 0;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    final conversations = await a.conversations();
    throw _DriveError(
      'routing timed out after 30s: currentConversation never resolved to '
      'toxB (c2c_$wantPk). last currentConversation=${last ?? '<null>'}; '
      'conversations=$conversations',
    );
  } on _DriveError catch (e) {
    print('[fixture-c-notif-tap] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

/// The Tox public key of a dump_state `currentConversation` entry, or null when
/// the entry is null or its conversationID does not carry one. Strips a leading
/// `c2c_`/`group_` prefix before extracting the key, matching the prefix-
/// agnostic comparison S53 requires.
String? _conversationPublicKey(Map<String, dynamic>? conversation) {
  if (conversation == null) return null;
  final raw = conversation['conversationID']?.toString() ?? '';
  if (raw.isEmpty) return null;
  return _toxPublicKey(_stripConversationPrefix(raw));
}

String _stripConversationPrefix(String conversationId) {
  for (final prefix in const ['c2c_', 'group_']) {
    if (conversationId.startsWith(prefix)) {
      return conversationId.substring(prefix.length);
    }
  }
  return conversationId;
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
      'ext.mcp.toolkit.l3_simulate_notification_tap',
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

  /// The top-level `currentConversation` from dump_state — the open/active
  /// conversation set by notification routing (null when no chat is open).
  Future<Map<String, dynamic>?> currentConversation() async {
    final s = await dumpState();
    final cur = s['currentConversation'];
    if (cur is Map) return Map<String, dynamic>.from(cur);
    return null;
  }

  /// The dump_state `conversations` list (for failure diagnostics).
  Future<List<Map<String, dynamic>>> conversations() async {
    final s = await dumpState();
    final raw = (s['conversations'] as List?) ?? const <dynamic>[];
    return <Map<String, dynamic>>[
      for (final c in raw)
        if (c is Map) Map<String, dynamic>.from(c),
    ];
  }

  Future<Map<String, dynamic>> simulateNotificationTap(
    String conversationId,
  ) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_simulate_notification_tap',
      <String, Object?>{'conversationId': conversationId},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-notif-tap][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-notif-tap][$name] booting restored account '
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
