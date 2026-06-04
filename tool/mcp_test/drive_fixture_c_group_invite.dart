// End-to-end driver for S47 "auto-accept group invite toggle" + S81 "invite a
// friend to a group" (one two-process gate).
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (after ensureReady) booted. A creates a group and INVITES the friend B to it
// (S81 invite-send). B has autoAcceptGroupInvites turned ON, so B auto-joins
// the group WITHOUT any manual join call (S47 auto-accept).
//
// Group-id keying note: l3_create_group returns a LOCAL group id (e.g.
// "tox_1") that the CREATOR (A) uses to key its own group, to address the
// invite, AND to send the group message. The friend B is invited by its tox id
// (userId), not by a chat-id, so no chat-id join is involved here.
//
// Observability note: when B auto-accepts the invite at the PROTOCOL level
// (C++ tox_group_invite_accept + HandleGroupSelfJoin), the auto-joined group
// does NOT appear in B's Dart-side `knownGroups` — the Dart layer only tracks
// groups it explicitly joined/created OR received a group MESSAGE in. So the
// observable proof that B auto-joined is: A sends a GROUP MESSAGE and B
// RECEIVES it (which also surfaces the group on B's side). We assert that,
// mirroring drive_fixture_c_group.dart's group-delivery poll (recompute the SET
// of candidate group keys from knownGroups ∪ type==2 conversation ids, then
// scan l3_dump_state{conversationId:'group_'+candidate}.messages for an
// inbound, isSelf==false, message with the exact nonce text).
//
// Sequence:
//   1. Connect A and B; ensureReady both; resolve toxA/toxB via
//      currentAccountToxId; wait connected + friend-online both directions.
//   2. B: l3_set_setting(autoAcceptGroupInvites,'true'); poll
//      dump_state.autoAcceptGroupInvites==true (<=10s). CONFIRM before invite.
//   3. A: l3_create_group(name:'l3_s47_<nonce>') -> capture LOCAL groupIdA.
//      FAIL if not ok / empty.
//   4. A: l3_invite_to_group(groupId: groupIdA, userId: toxB). A freshly
//      created NGC group needs to announce before the invite transmits, so the
//      invite is retried. Assert ok==true (code==0). On failure print code+desc
//      and FAIL (the S81 invite-send leg). PASS A1 (invite sent).
//   5. PRIMARY (S47 auto-accept, observable): give B ~10s to auto-accept+join,
//      then A sends a group message ('S47 invite <nonce>') via groupIdA. Poll B
//      up to ~150s, re-sending the group text every ~25s AND re-inviting on
//      each round, for an inbound (isSelf==false) message with the exact nonce
//      text under ANY candidate group key. As soon as B observes it -> PASS A2
//      (B auto-joined via invite + receives group messages). On timeout print
//      B's knownGroups + conversations(type==2) + candidate group histories.
//   6. CLEANUP (finally): B restore autoAcceptGroupInvites=false (runs even on
//      failure).
//   7. Return 0 all-pass / 1 fail / 64 usage.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_group_invite.dart \
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
      'usage: drive_fixture_c_group_invite.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path/to/paired_for_e2e_manifest.json]',
    );
    return 64;
  }
  final fixture = fixtureManifestPath == null
      ? null
      : await _FixtureManifest.load(fixtureManifestPath);
  final a = await _PairDriver.connect('A', positional[0]);
  final b = await _PairDriver.connect('B', positional[1]);
  var restoreAutoAccept = false;
  try {
    if (fixture != null) {
      await a.ensureReady(fixture: fixture.a);
      await b.ensureReady(fixture: fixture.b);
    } else {
      print('[fixture-c-group-invite] no manifest; assuming both ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // Full-mesh loopback bootstrap so A and B discover each other as NGC peers
    // before the group create/invite flow (same-host public-DHT discovery is
    // slow/flaky).
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
      '[fixture-c-group-invite] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    // 2. B: turn autoAcceptGroupInvites ON and CONFIRM it stuck BEFORE the
    // invite is sent, else B would not auto-join. l3_set_setting drives the
    // LIVE setter via the applier, syncing the C++ auto-accept flag.
    restoreAutoAccept = true;
    await b.setSetting('autoAcceptGroupInvites', 'true');
    await b.waitForAutoAcceptGroupInvites(expected: true, timeoutSecs: 10);
    print('[fixture-c-group-invite] B autoAcceptGroupInvites=true confirmed');

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    // 3. A creates the group. l3_create_group returns the LOCAL groupId (what A
    // uses to address the invite AND to send the group message).
    final created = await a.createGroup(name: 'l3_s47_$nonce');
    final groupIdA = created.groupId;
    if (groupIdA.isEmpty) {
      throw _DriveError(
        'create_group returned an empty local groupId '
        '(chatId="${created.chatId}" len=${created.chatId.length})',
      );
    }
    print('[fixture-c-group-invite] A created group localGroupId="$groupIdA"');

    // 4. A freshly-created NGC group is not yet DHT-connected, and
    // tox_group_invite_friend silently no-ops (returns ok locally but does NOT
    // transmit) while the group is disconnected. So: let the group announce,
    // then invite in a RETRY loop — later attempts land after the group has
    // connected. We only require the invite to be SENT here (S81); the
    // observable auto-join proof comes in step 5.
    await Future<void>.delayed(const Duration(seconds: 15));
    var inviteSent = false;
    for (var attempt = 1; attempt <= 4 && !inviteSent; attempt++) {
      final invite = await a.inviteToGroup(groupId: groupIdA, userId: toxB);
      if (invite.ok) {
        inviteSent = true;
        print(
          '[fixture-c-group-invite] invite attempt $attempt sent (code=${invite.code})',
        );
      } else {
        print(
          '[fixture-c-group-invite] invite attempt $attempt code=${invite.code} '
          'desc="${invite.desc}"',
        );
        await Future<void>.delayed(const Duration(seconds: 5));
      }
    }
    if (!inviteSent) {
      throw _DriveError(
        'l3_invite_to_group never returned ok across attempts (S81 send leg)',
      );
    }
    print('[fixture-c-group-invite] PASS A1 invite-sent (S81)');

    // 5. PRIMARY (S47 auto-accept), made OBSERVABLE: the auto-joined group does
    // NOT show up in B's Dart-side knownGroups, so we prove the auto-join by
    // having A send a GROUP MESSAGE and confirming B RECEIVES it (which both
    // proves B is in the group AND surfaces the group on B's side). Give B ~10s
    // to auto-accept+join after the invite, then send the first group text.
    await Future<void>.delayed(const Duration(seconds: 10));
    final groupText = 'S47 invite $nonce';
    await a.sendGroupText(groupIdA, groupText);
    print('[fixture-c-group-invite] A sent group text "$groupText"');

    // Poll B up to ~150s, re-sending the group text every ~25s AND re-inviting
    // on each round (the group may only just have connected / B may only just
    // have joined). As soon as B observes the inbound nonce text under ANY
    // candidate group key, the auto-join (S47) is confirmed observably.
    final observedKey = await _pollGroupInbound(
      sender: a,
      senderGroupId: groupIdA,
      groupText: groupText,
      inviter: a,
      groupId: groupIdA,
      inviteeToxId: toxB,
      observer: b,
      timeoutSecs: 150,
      resendEverySecs: 25,
    );
    print(
      '[fixture-c-group-invite] PASS A2 auto-joined+received (S47) '
      '(key=$observedKey)',
    );

    print('[fixture-c-group-invite] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-group-invite] ERROR: ${e.message}');
    return 1;
  } finally {
    if (restoreAutoAccept) {
      try {
        await b.setSetting('autoAcceptGroupInvites', 'false');
        print(
          '[fixture-c-group-invite] cleanup: B autoAcceptGroupInvites restored',
        );
      } catch (e) {
        print(
          '[fixture-c-group-invite] cleanup: restore autoAccept failed: $e',
        );
      }
    }
    await a.dispose();
    await b.dispose();
  }
}

/// Collect the SET of candidate group ids `driver` might key its group history
/// under: every entry of base-dump `knownGroups`, PLUS — for every
/// `conversations` entry of type 2 (group) — its conversationID with a leading
/// 'group_' stripped. Used so READS try ALL keys (creator keys by local id,
/// joiner/auto-joiner may surface a chat-id, native may use other ids).
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
/// the exact `groupText`, scanning across ALL candidate group keys (recomputed
/// each pass via [_groupCandidates]). Returns the candidate key that matched —
/// this is the OBSERVABLE proof that B auto-joined via the invite. The group
/// may only just have connected / B may only just have auto-joined, so every
/// `resendEverySecs` the `sender` re-sends `groupText` AND the `inviter`
/// re-invites the `inviteeToxId`. On timeout, dump the observer's knownGroups +
/// group-typed conversations + each candidate's messages and throw.
Future<String> _pollGroupInbound({
  required _PairDriver sender,
  required String senderGroupId,
  required String groupText,
  required _PairDriver inviter,
  required String groupId,
  required String inviteeToxId,
  required _PairDriver observer,
  required int timeoutSecs,
  required int resendEverySecs,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  var lastResend = DateTime.now();
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
            m['text']?.toString() == groupText) {
          return candidate;
        }
      }
    }
    // Periodically nudge: re-invite (in case the auto-accept hadn't fired yet)
    // and re-send the group text (in case the earlier send dropped before the
    // group/peer was connected).
    if (DateTime.now().difference(lastResend).inSeconds >= resendEverySecs) {
      lastResend = DateTime.now();
      final invite = await inviter.inviteToGroup(
        groupId: groupId,
        userId: inviteeToxId,
      );
      print(
        '[fixture-c-group-invite] re-invite (ok=${invite.ok} '
        'code=${invite.code}) + re-send group text',
      );
      try {
        await sender.sendGroupText(senderGroupId, groupText);
      } on _DriveError catch (e) {
        print('[fixture-c-group-invite] re-send group text failed: ${e.message}');
      }
    }
    await Future<void>.delayed(const Duration(seconds: 2));
  }
  // Timeout diagnostics: knownGroups + group-typed conversations + each
  // candidate's compact messages.
  final base = await observer.dumpState();
  final known = (base['knownGroups'] as List?) ?? const <dynamic>[];
  final convs = (base['conversations'] as List?) ?? const <dynamic>[];
  final groupConvs = <Map<String, Object?>>[
    for (final c in convs)
      if (c is Map && c['type'] == 2)
        {'conversationID': c['conversationID'], 'type': c['type']},
  ];
  print('[fixture-c-group-invite][${observer.name}] timeout; knownGroups=$known');
  print(
    '[fixture-c-group-invite][${observer.name}] conversations(type==2)=$groupConvs',
  );
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
      '[fixture-c-group-invite][${observer.name}] candidate "$candidate" '
      'messages=$summary',
    );
  }
  throw _DriveError(
    'B never received the group message "$groupText" within ${timeoutSecs}s '
    '(S47 auto-join not observable) across candidates=$candidates',
  );
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

/// The two ids l3_create_group returns: a LOCAL group id (creator's history
/// key, used to address the invite) and the joinable 64-char hex chat-id.
class _CreatedGroup {
  _CreatedGroup({required this.groupId, required this.chatId});
  final String groupId;
  final String chatId;
}

/// Result of l3_invite_to_group: {ok, code, desc}. ok==true means code==0.
class _InviteResult {
  _InviteResult({required this.ok, required this.code, required this.desc});
  final bool ok;
  final int code;
  final String desc;
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
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_invite_to_group',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_send_group_text',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_set_setting',
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
      print('[fixture-c-group-invite][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-group-invite][$name] booting restored account '
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

  /// Create a group; returns BOTH the LOCAL group id (used to address the
  /// invite) and the joinable 64-char hex chat-id.
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

  /// Invite a friend (by tox id [userId]) to the group [groupId] (the LOCAL
  /// groupId from create). Returns {ok, code, desc}; ok==true means code==0.
  Future<_InviteResult> inviteToGroup({
    required String groupId,
    required String userId,
  }) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_invite_to_group',
      <String, Object?>{'groupId': groupId, 'userId': userId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    final ok = json['ok'] == true;
    final code = (json['code'] is num)
        ? (json['code'] as num).toInt()
        : int.tryParse(json['code']?.toString() ?? '') ?? -1;
    final desc = json['desc']?.toString() ?? '';
    return _InviteResult(ok: ok, code: code, desc: desc);
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

  Future<void> setSetting(String key, String value) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_set_setting',
      <String, Object?>{'key': key, 'value': value},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        '[$name] l3_set_setting $key=$value failed: ${json['error']}',
      );
    }
  }

  Future<void> waitForAutoAcceptGroupInvites({
    required bool expected,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      if (state['autoAcceptGroupInvites'] == expected) {
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError(
      '[$name] autoAcceptGroupInvites did not become $expected',
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
