// End-to-end driver for the S78 "voice message record + send" L3 scenario
// (two-process voice transfer).
//
// In toxee a "voice message" is simply a file send whose extension makes the
// app's _detectKind return mediaKind='audio'. The audio extensions are
// .mp3 .wav .m4a .aac .ogg .flac. The inline content is irrelevant — kind
// detection keys on the .ogg EXTENSION, not the bytes. This driver runs the
// same paired flow as drive_fixture_c_file.dart (S21/S24), but the file is an
// audio file and the assertions additionally require mediaKind=='audio'.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends. The
// driver boots both restored accounts via l3_boot_existing_account, so the gate
// does NOT need a separate boot step. Because the receiver auto-accepts files
// under its size limit, one small audio file covers both legs:
//   - S78 (send leg):    an audio file message exists on the SENDER (A) side.
//   - S78 (receive leg):  the audio file message arrives on the RECEIVER (B)
//                          side AND B accepted + wrote it (filePath is set).
//
// Sequence:
//   1. Connect A and B; ensureReady both (boots restored accounts).
//      waitForConnected; waitForFriendOnline both directions; resolve toxA/toxB.
//   2. Generate a per-run nonce; build voice fileName (.ogg) + inline content.
//   3. A: l3_send_file(userId: toxB, fileName, content).
//   4. S78 send leg: poll A's C2C(toxB) for an isSelf message whose filePath
//      basename matches our fileName AND mediaKind=='audio'.
//   5. S78 receive leg: poll B's C2C(toxA) for a non-self message with our
//      fileName, a non-empty filePath (proves B accepted + wrote the file),
//      AND mediaKind=='audio'.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_voice_msg.dart \
//       <ws_uri_A> <ws_uri_B> --fixture-manifest path

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
      'usage: drive_fixture_c_voice_msg.dart <ws_uri_A> <ws_uri_B> '
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
      print('[fixture-c-voice-msg] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    final toxA = await a.currentToxId();
    final toxB = await b.currentToxId();
    if (toxA.isEmpty || toxB.isEmpty) {
      throw _DriveError('missing tox ids: A=$toxA B=$toxB');
    }
    print(
      '[fixture-c-voice-msg] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();
    // .ogg extension => _detectKind returns mediaKind='audio'. Content bytes
    // are irrelevant; kind detection keys on the extension, not the content.
    final fileName = 'voice-$nonce.ogg';
    final content = 'OggS fake voice $nonce';
    print('[fixture-c-voice-msg] nonce=$nonce fileName=$fileName');

    // 3. A sends the voice file (inline content -> app writes a sandbox-safe
    //    temp src).
    await a.sendFile(userId: toxB, fileName: fileName, content: content);
    print('[fixture-c-voice-msg] voice file send issued');

    // 4. S78 send leg: an isSelf audio message for our file exists on A.
    await a.waitForSentVoice(
      conversationId: toxB,
      fileName: fileName,
      timeoutSecs: 60,
    );
    print('[fixture-c-voice-msg] PASS A1 send(audio)');

    // 5. S78 receive leg (PRIMARY): the audio file arrives on B and B accepted
    //    + wrote it (filePath set, mediaKind=='audio'). DHT transfer is slower
    //    than text.
    await b.waitForReceivedVoice(
      conversationId: toxA,
      fileName: fileName,
      timeoutSecs: 180,
    );
    print('[fixture-c-voice-msg] PASS A2 receive(audio)');

    print('[fixture-c-voice-msg] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-voice-msg] ERROR: ${e.message}');
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
    await d.waitForExtension('ext.mcp.toolkit.l3_send_file', timeoutSecs: 60);
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
      print('[fixture-c-voice-msg][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-voice-msg][$name] booting restored account '
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

  Future<void> sendFile({
    required String userId,
    required String fileName,
    required String content,
  }) async {
    final resp = await _call('ext.mcp.toolkit.l3_send_file', <String, Object?>{
      'userId': userId,
      'fileName': fileName,
      'content': content,
    });
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_send_file failed: '
        'error=${json['error']} detail=${json['detail']}',
      );
    }
  }

  // S78 send leg: an isSelf audio message for our file exists on this side.
  // The sender-side ChatMessage sets filePath + mediaKind but NOT fileName
  // (ffi_chat_service.dart:5913 — the UI derives the display name from the
  // path basename), so match on the filePath basename, and require
  // mediaKind=='audio' (proves the .ogg extension was classified as a voice
  // message), not on the fileName field.
  Future<void> waitForSentVoice({
    required String conversationId,
    required String fileName,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    List<Map<String, dynamic>> lastMessages = const [];
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(conversationId: conversationId);
      lastMessages = _messagesOf(state);
      for (final m in lastMessages) {
        final isSelf = m['isSelf'] == true;
        final filePath = m['filePath']?.toString() ?? '';
        final base = filePath.isEmpty ? '' : filePath.split('/').last;
        final mediaKind = m['mediaKind']?.toString() ?? '';
        if (isSelf && base == fileName && mediaKind == 'audio') {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _printMessageSummary(lastMessages);
    throw _DriveError(
      '[$name] sent voice "$fileName" (mediaKind=audio) not found on sender '
      'side of ${conversationId.substring(0, 16)} within ${timeoutSecs}s',
    );
  }

  // S78 receive leg: a non-self audio message with our fileName arrived AND has
  // a non-empty filePath (proves B accepted + wrote the file) AND
  // mediaKind=='audio'.
  Future<void> waitForReceivedVoice({
    required String conversationId,
    required String fileName,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    List<Map<String, dynamic>> lastMessages = const [];
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState(conversationId: conversationId);
      lastMessages = _messagesOf(state);
      for (final m in lastMessages) {
        final isSelf = m['isSelf'] == true;
        final name = m['fileName']?.toString() ?? '';
        final filePath = m['filePath']?.toString() ?? '';
        final base = filePath.isEmpty ? '' : filePath.split('/').last;
        final mediaKind = m['mediaKind']?.toString() ?? '';
        // Received message sets fileName; match it, but also accept the
        // written-path basename in case the receiver uniquified the name.
        if (!isSelf &&
            filePath.isNotEmpty &&
            mediaKind == 'audio' &&
            (name == fileName || base == fileName)) {
          return;
        }
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    _printMessageSummary(lastMessages);
    throw _DriveError(
      '[$name] received voice "$fileName" (mediaKind=audio) with a written '
      'filePath not found on receiver side of '
      '${conversationId.substring(0, 16)} within ${timeoutSecs}s',
    );
  }

  void _printMessageSummary(List<Map<String, dynamic>> messages) {
    print('[fixture-c-voice-msg][$name] last ${messages.length} messages:');
    for (final m in messages) {
      print(
        '  msgID=${m['msgID']} isSelf=${m['isSelf']} '
        'fileName=${m['fileName']} filePath=${m['filePath']} '
        'mediaKind=${m['mediaKind']}',
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
