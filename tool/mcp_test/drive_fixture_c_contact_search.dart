// End-to-end driver for the S49 "contact-list search filter" L3 scenario
// (B-block: in-page contact search filter).
//
// This validates the in-page contact-search FILTER deterministically. The
// search field itself renders in the contact AppBar with
// ValueKey('contact_search_field') — the fix that un-stubbed the prior
// Container() placeholder. This driver does NOT exercise rendered keystrokes;
// it drives the filter over A's local contact list via the l3_contact_search
// tool and gates the resulting counts.
//
// This scenario drives instance A only. B is booted purely as the paired
// partner that the manifest carries, so that A's friend list (which hydrates
// from the restored paired_for_e2e fixture) is populated. The contact list is
// local to A — no live friend-online state is required for the filter.
//
// On the paired_for_e2e fixture, A has exactly ONE friend with nickname
// 'echo_live_test'.
//
// Tool:
//   l3_contact_search {query} -> {ok:true, query, filteredCount:int}
//     Runs the in-page contact-search filter (case-insensitive remark / nick /
//     userID "contains") over A's contact list and returns the count. An empty
//     query returns the full contact count.
//
// Sequence:
//   1. Connect A and B; ensureReady (boot restored accounts) both;
//      waitForConnected(60) both. (B booted only because the manifest carries
//      it.) waitForFriendOnline is NOT required — the contact list is local.
//      Poll A until its contact list hydrates: l3_contact_search('') until
//      filteredCount >= 1 (<=60s, poll every 2s).
//   2. FULL: full = l3_contact_search('').filteredCount; assert full >= 1.
//   3. MATCH: match = l3_contact_search('echo').filteredCount; the sole friend
//      'echo_live_test' matches 'echo'. Assert match >= 1 AND match <= full.
//      PASS A1.
//   4. NO-MATCH: l3_contact_search('zzz_no_such_contact_<nonce>').filteredCount;
//      assert == 0. PASS A2.
//   5. Return 0 on PASS, 1 on assertion/drive error, 64 on usage error.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_contact_search.dart \
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
      'usage: drive_fixture_c_contact_search.dart <ws_uri_A> <ws_uri_B> '
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
        '[fixture-c-contact-search] no manifest; assuming both sessions ready',
      );
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // 1. The contact list is local to A; wait for it to hydrate after boot.
    //    (B is booted only because the manifest carries it.)
    await a.waitForContactList(timeoutSecs: 60);

    // 2. FULL count.
    final full = await a.contactSearchCount('');
    if (full < 1) {
      throw _DriveError('expected full contact count >= 1, got $full');
    }
    print('[fixture-c-contact-search] full=$full');

    // 3. MATCH: this fixture's contact has no human-readable nickname in A's
    //    contact data, but its searchable userID IS B's Tox id — so search a
    //    prefix of it (case-insensitive contains match on userID).
    final toxB = fixture?.b.toxId ?? '';
    if (toxB.length < 8) {
      throw _DriveError(
        'could not resolve toxB (need --fixture-manifest) for the match query',
      );
    }
    final matchQuery = toxB.substring(0, 8);
    final match = await a.contactSearchCount(matchQuery);
    if (match < 1) {
      throw _DriveError(
        'matching query "$matchQuery" returned $match (expected >= 1)',
      );
    }
    if (match > full) {
      throw _DriveError(
        'matching query "$matchQuery" returned $match > full $full (impossible)',
      );
    }
    print('[fixture-c-contact-search] PASS A1 match ($matchQuery=$match)');

    // 4. NO-MATCH: a per-run nonce guarantees no contact can match.
    final nonce = DateTime.now().microsecondsSinceEpoch;
    final noMatchQuery = 'zzz_no_such_contact_$nonce';
    final noMatch = await a.contactSearchCount(noMatchQuery);
    if (noMatch != 0) {
      throw _DriveError(
        'non-matching query "$noMatchQuery" returned $noMatch (expected 0)',
      );
    }
    print('[fixture-c-contact-search] PASS A2 no-match (0)');

    print('[fixture-c-contact-search] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-contact-search] ERROR: ${e.message}');
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
      'ext.mcp.toolkit.l3_contact_search',
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

  /// Runs the in-page contact-search filter over A's contact list and returns
  /// the filtered count. An empty [query] returns the full contact count.
  Future<int> contactSearchCount(String query) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_contact_search',
      <String, Object?>{'query': query},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_contact_search("$query") failed: ${json['error']} '
        '(detail=${json['detail']})',
      );
    }
    final count = json['filteredCount'];
    if (count is! int) {
      throw _DriveError(
        '[$name] l3_contact_search("$query") returned non-int filteredCount: '
        '$count',
      );
    }
    return count;
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-contact-search][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-contact-search][$name] booting restored account '
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

  /// Polls the contact-search filter (empty query => full count) every 2s up to
  /// [timeoutSecs] until A's contact list has hydrated (filteredCount >= 1).
  Future<void> waitForContactList({required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    var lastCount = -1;
    while (DateTime.now().isBefore(deadline)) {
      final count = await contactSearchCount('');
      if (count != lastCount) {
        print(
          '[fixture-c-contact-search][$name] contact list size=$count',
        );
        lastCount = count;
      }
      if (count >= 1) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 2));
    }
    throw _DriveError(
      '[$name] contact list did not hydrate (filteredCount stayed at '
      '$lastCount)',
    );
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
