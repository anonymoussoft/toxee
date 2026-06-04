// End-to-end driver for the S79 "set self avatar via native picker" L3
// scenario.
//
// The native macOS NSOpenPanel cannot be driven headlessly, so this scenario
// CANNOT exercise the OS file-picker UI directly. Instead the L3 override
// (l3_pick_avatar) BYPASSES the native picker — it writes a sandbox-safe temp
// source file from the supplied `content`, then exercises the REAL
// pickAndPersistAvatar copy+persist flow: the temp source is copied into the
// per-account avatars dir and the resulting path is persisted as the self
// avatar. Only that copy+persist leg is gated here.
//
// This driver only asserts on instance A. B is booted as the paired partner so
// the harness launch is unchanged (the paired manifest carries both accounts),
// but no assertion touches B. Friend propagation of the avatar (a kind-1 /
// TOX_FILE_KIND_AVATAR file transfer) is the SEPARATE S52 gate and is NOT
// covered here.
//
// Sequence:
//   1. Connect A and B; ensureReady (boot restored accounts); waitForConnected
//      both (only A is strictly needed, but boot B since the manifest has it).
//      Resolve toxA via currentAccountToxId.
//   2. Build a per-run nonce; on A call l3_pick_avatar(content:'S79-pick-<nonce>').
//   3. Assert the response ok==true AND destPath is a non-empty string ending in
//      '.png' that contains 'avatar' or 'avatars' (it was copied into the
//      per-account avatars dir as avatar_<id>_<ts>.png or self_avatar_<ts>.png).
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_avatar_picker.dart \
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
      'usage: drive_fixture_c_avatar_picker.dart <ws_uri_A> <ws_uri_B> '
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
        '[fixture-c-avatar-picker] no manifest; assuming both sessions ready',
      );
    }
    // Only A is strictly needed for the assertions, but boot B too since the
    // paired manifest carries both accounts.
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    if (toxA.isEmpty) {
      throw _DriveError('missing tox id: A=$toxA');
    }
    print(
      '[fixture-c-avatar-picker] toxA=${toxA.substring(0, 16)}...',
    );

    // 2. Per-run nonce; drive the real pick+persist flow on A.
    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    final content = 'S79-pick-$nonce';
    print('[fixture-c-avatar-picker] picking avatar content="$content"');
    final resp = await a.pickAvatar(content: content);

    // 3. Assert ok==true and destPath is a plausible per-account avatar path.
    final ok = resp['ok'] == true;
    final destPath = resp['destPath']?.toString() ?? '';
    final lower = destPath.toLowerCase();
    final pathOk = destPath.isNotEmpty &&
        lower.endsWith('.png') &&
        (lower.contains('avatar') || lower.contains('avatars'));
    if (!ok || !pathOk) {
      print('[fixture-c-avatar-picker] full response: $resp');
      throw _DriveError(
        'l3_pick_avatar did not return a valid persisted avatar path; '
        'ok=$ok destPath="$destPath"',
      );
    }

    print('[fixture-c-avatar-picker] PASS (destPath=$destPath)');
    print('[fixture-c-avatar-picker] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-avatar-picker] ERROR: ${e.message}');
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
      'ext.mcp.toolkit.l3_pick_avatar',
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
      print('[fixture-c-avatar-picker][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-avatar-picker][$name] booting restored account '
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

  /// Drives the real pick+persist avatar flow with the native picker bypassed:
  /// l3_pick_avatar writes a sandbox-safe temp source from [content], copies it
  /// into the per-account avatars dir, persists the path, and returns
  /// {ok:true, destPath}.
  Future<Map<String, dynamic>> pickAvatar({required String content}) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_pick_avatar',
      <String, Object?>{'content': content},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
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
