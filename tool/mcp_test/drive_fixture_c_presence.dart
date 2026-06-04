// Presence probe for the S51 "friend online/offline presence indicator"
// L3 scenario.
//
// Connects to a single running toxee instance's VM service, waits for the
// l3_dump_state extension, then polls l3_dump_state (every 1s, up to a
// timeout) until the selected friend's `online` flag matches the expected
// value. Used by run_fixture_c_presence.sh to drive A while B is taken
// offline / brought back online.
//
// Usage:
//   dart run tool/mcp_test/drive_fixture_c_presence.dart \
//     <ws_uri> <expectedOnline:true|false> \
//     [--timeout-secs 120] [--friend-tox <id>]

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:io';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  final positional = <String>[];
  var timeoutSecs = 120;
  String? friendTox;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--timeout-secs') {
      if (i + 1 >= args.length) {
        print('usage: --timeout-secs requires a value');
        return 64;
      }
      final parsed = int.tryParse(args[++i]);
      if (parsed == null || parsed <= 0) {
        print('usage: --timeout-secs must be a positive integer');
        return 64;
      }
      timeoutSecs = parsed;
    } else if (arg == '--friend-tox') {
      if (i + 1 >= args.length) {
        print('usage: --friend-tox requires an id');
        return 64;
      }
      friendTox = args[++i];
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_presence.dart <ws_uri> '
      '<expectedOnline:true|false> [--timeout-secs 120] [--friend-tox <id>]',
    );
    return 64;
  }
  final wsUri = positional[0];
  final expectedRaw = positional[1].toLowerCase();
  final bool expectedOnline;
  if (expectedRaw == 'true') {
    expectedOnline = true;
  } else if (expectedRaw == 'false') {
    expectedOnline = false;
  } else {
    print('usage: <expectedOnline> must be "true" or "false"');
    return 64;
  }

  final driver = await _PresenceDriver.connect(wsUri);
  try {
    await driver.waitForExpected(
      expectedOnline: expectedOnline,
      timeoutSecs: timeoutSecs,
      friendTox: friendTox,
    );
    return 0;
  } on _DriveError catch (e) {
    print('[presence] ERROR: ${e.message}');
    return 1;
  } finally {
    await driver.dispose();
  }
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

class _PresenceDriver {
  _PresenceDriver(this.vm, this.isolateId);

  final VmService vm;
  final String isolateId;

  static Future<_PresenceDriver> connect(String wsUri) async {
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final d = _PresenceDriver(vm, isolateId);
    await d.waitForExtension('ext.mcp.toolkit.l3_dump_state', timeoutSecs: 60);
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
    throw _DriveError('extension $name not registered');
  }

  Future<Map<String, dynamic>> dumpState() async {
    final resp = await vm.callServiceExtension(
      'ext.mcp.toolkit.l3_dump_state',
      isolateId: isolateId,
      args: const <String, String>{},
    );
    return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
  }

  Future<void> waitForExpected({
    required bool expectedOnline,
    required int timeoutSecs,
    String? friendTox,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    bool? lastObserved;
    List<dynamic> lastFriends = const <dynamic>[];
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      final friends = (state['friends'] as List?) ?? const <dynamic>[];
      lastFriends = friends;
      final friend = _selectFriend(friends, friendTox);
      final online = friend['online'] == true;
      if (lastObserved != online) {
        print('[presence] friend online=$online');
        lastObserved = online;
      }
      if (online == expectedOnline) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      'timed out after ${timeoutSecs}s waiting for friend online='
      '$expectedOnline; last friends snapshot=$lastFriends',
    );
  }

  Map<String, dynamic> _selectFriend(List<dynamic> friends, String? friendTox) {
    final maps = <Map<String, dynamic>>[
      for (final f in friends)
        if (f is Map) Map<String, dynamic>.from(f),
    ];
    if (friendTox != null) {
      final wantPk = _toxPublicKey(friendTox);
      for (final f in maps) {
        final friendId = f['userId']?.toString() ?? '';
        if (_toxPublicKey(friendId) == wantPk) {
          return f;
        }
      }
      throw _DriveError(
        'friend matching --friend-tox ${_short(friendTox)} not found in '
        'friends list=$friends',
      );
    }
    if (maps.isEmpty) {
      throw _DriveError(
        'friends list is empty; cannot auto-select a friend (pass --friend-tox)',
      );
    }
    if (maps.length > 1) {
      throw _DriveError(
        'friends list has ${maps.length} entries; pass --friend-tox to '
        'disambiguate; friends list=$friends',
      );
    }
    return maps.first;
  }
}

String _short(String id) =>
    id.length >= 16 ? '${id.substring(0, 16)}...' : id;

String _toxPublicKey(String userId) {
  final normalized = userId.trim().toUpperCase();
  return normalized.length >= 64 ? normalized.substring(0, 64) : normalized;
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
