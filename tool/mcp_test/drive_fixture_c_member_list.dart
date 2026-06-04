// End-to-end driver for the S36 "group member list" L3 scenario.
//
// LIVE-VALIDATION OWED: this gate is the READ-ONLY subset of the S37 KICK
// driver (drive_fixture_c_kick.dart) and has NOT been run against a live paired
// fixture yet — it shares the kick's residual NGC two-process peer-connectivity
// flakiness (see below). Run `run_fixture_c_member_list.sh` (which retries fresh
// paired sessions) to validate, then drop this notice.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (after ensureReady) booted. A creates a PUBLIC NGC group; l3_create_group
// returns BOTH a LOCAL group id (e.g. "tox_1", used by the creator to key its
// own state) AND a separate 64-char hex `chatId` (the joinable public group
// id). B joins by that chat-id — the PROVEN S34 path — to get into the group
// reliably (no invite, which avoids the invite-delivery issue).
//
// S36 CONTRACT (what this gate asserts, kick DROPPED): once B is a member, A's
// l3_group_member_list(localGroupIdA) returns a member list that:
//   - has memberCount >= 2 (self + the joined peer),
//   - includes EXACTLY ONE entry with isSelf:true (A itself — its self entry
//     carries A's GLOBAL Tox pubkey; l3_group_member_list flags it by matching
//     the current account), and
//   - includes AT LEAST ONE non-self member (B), identified by its NGC
//     GROUP-SPECIFIC public key (NOT the friend/Tox pubkey — NGC members are
//     keyed per-group). A non-self member appearing PROVES A's group peer cache
//     holds B.
//
// MEMBER-LIST shape (lib/ui/testing/l3_debug_tools.dart `_l3GroupMemberListEntry`):
//   {ok, groupId, memberCount, members:[{userID, nickName, role, isSelf}], nextSeq}
// where for a REMOTE member userID is its per-group pubkey and for the self
// entry userID is this account's global Tox pubkey.
//
// NGC PEER CONNECTIVITY (the residual — SAME as the kick): live, the founder's
// HandleGroupPeerJoin did NOT fire (A's group_peer_id_cache_ stayed at 0 peers
// for 90s) AND group messages did not roundtrip — because same-host instances
// only bootstrap to the PUBLIC DHT, never to each other, so PUBLIC-group peer
// discovery never converges. The tim2tox auto_tests fix this with a full-mesh
// LOCAL bootstrap (their comment names this exact "peer_join never fires on
// founder" symptom). FIX: the driver wires a full-mesh loopback bootstrap
// (l3_dht_info + l3_add_bootstrap_node) so A and B discover each other locally;
// once peers connect, HandleGroupPeerJoin fires and A's cache populates. A's
// cache can ALSO populate via HandleGroupMessageGroup when A receives a group
// message (V2TIMManagerImpl.cpp:4893), so the resolve step nudges with a B->A
// message each round (best-effort) and treats A's member list as authoritative.
// If B never enters A's cache the poll fails LOUDLY with the stalled stage (the
// loud-failure diagnostic is kept verbatim from the kick driver).
//
// Sequence:
//   1. Connect A and B; ensureReady both; wait connected (60s); FULL-MESH
//      loopback bootstrap A<->B (l3_dht_info + l3_add_bootstrap_node) so
//      same-host NGC peers discover each other; resolve toxA/toxB; wait
//      friend-online both directions (120s).
//   2. A: l3_create_group(name) -> capture LOCAL groupIdA AND the 64-hex chatId.
//      Validate the chatId is 64-hex (it is what B joins with).
//   3. B JOINS the chat-id, retrying ~6x (3s spacing) for DHT lag, then poll
//      B.knownGroups (up to 90s) until it GROWS to include the joined group
//      => PASS A1 (B is a member).
//   4. RESOLVE (robust): each round B nudges a group message (best-effort) and
//      A polls l3_group_member_list(groupIdA) (up to 150s) until a NON-SELF
//      member appears; capture its userID = B's NGC group pubkey. A's cache
//      populates via peer-join (bootstrap) OR a received message — the member
//      list is authoritative, so the flaky group message is never required.
//   5. ASSERT S36: re-read A's member list ONE more time and assert
//      memberCount >= 2, EXACTLY ONE isSelf:true, and the resolved non-self
//      member is present => PASS A2 (member list shows BOTH self and B).
//   6. Return 0 all-pass / 1 fail / 64 usage.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_member_list.dart \
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
      'usage: drive_fixture_c_member_list.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path]',
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
      print('[fixture-c-member-list] no manifest; assuming both sessions ready');
    }
    await a.waitForConnected(timeoutSecs: 60);
    await b.waitForConnected(timeoutSecs: 60);

    // Full-mesh loopback bootstrap so A and B discover each other as NGC peers
    // before any group activity — the fix for same-host NGC peer discovery
    // (shared helper; see fixture_c_bootstrap.dart).
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
      '[fixture-c-member-list] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    // ===== PUBLIC + JOIN (DHT discovery; the proven S34/S37 flow) =====
    // 2. A creates the public NGC group: BOTH a LOCAL group id AND the joinable
    // 64-char hex chatId (what B joins with). Validate the chatId shape.
    final created = await a.createGroup(name: 'l3_s36_$nonce');
    final groupIdA = created.groupId;
    final chatId = created.chatId;
    if (groupIdA.isEmpty) {
      throw _DriveError(
        'create_group returned an empty local groupId '
        '(chatId="$chatId" len=${chatId.length})',
      );
    }
    if (!_isChatId(chatId)) {
      throw _DriveError(
        'create_group chatId is not 64-char hex (cannot be joined): '
        'groupId="$groupIdA" (len=${groupIdA.length}) '
        'chatId="$chatId" (len=${chatId.length}).',
      );
    }
    print(
      '[fixture-c-member-list] created group: localGroupId="$groupIdA" '
      'chatId=${chatId.substring(0, 16)}... (64-hex)',
    );

    // 3. B JOINS by chat-id (PROVEN S34 path; no invite). DHT discovery can
    // lag, so retry; confirm membership by watching B.knownGroups GROW.
    final baseKnownB = await b.knownGroups();
    print('[fixture-c-member-list] B baseline knownGroups=$baseKnownB');
    await b.joinGroupWithRetry(chatId, attempts: 6, spacingMs: 3000);
    final joinedId = await _waitForGroupAdded(
      b,
      baseline: baseKnownB,
      timeoutSecs: 90,
    );
    print(
      '[fixture-c-member-list] PASS A1 joined '
      '(B.knownGroups gained "$joinedId")',
    );

    // 4. RESOLVE (robust nudge-and-poll). A's cache populates via peer-join
    // (bootstrap) OR HandleGroupMessageGroup on a received B->A message
    // (V2TIMManagerImpl.cpp:4893); the message roundtrip is flaky, so nudge
    // best-effort and treat A's member list as authoritative.
    final bGroupPk = await _waitForOtherMember(
      a,
      groupId: groupIdA,
      nudgeJoiner: b,
      nudgeGroupId: chatId,
      nonce: nonce,
      timeoutSecs: 150,
    );
    print(
      '[fixture-c-member-list] A resolved B group identity '
      '${bGroupPk.substring(0, 16)}... (NOT friend toxB '
      '${toxB.substring(0, 16)}...)',
    );

    // 5. ASSERT S36: re-read A's member list and check the full contract —
    // memberCount >= 2, EXACTLY ONE self entry, and the resolved non-self
    // member (B) is present. The list shows BOTH self and the joined peer.
    final members = await a.groupMembers(groupIdA);
    final selfMembers = members.where((m) => m['isSelf'] == true).toList();
    final nonSelfMembers = members
        .where((m) => m['isSelf'] != true && ((m['userID'] as String?) ?? '').isNotEmpty)
        .toList();
    final wantPk = bGroupPk.toLowerCase();
    final bStillPresent = nonSelfMembers.any(
      (m) => ((m['userID'] as String?) ?? '').toLowerCase() == wantPk,
    );

    if (members.length < 2) {
      await _dumpGroupDiagnostics(a, reason: 'member list < 2');
      print('[fixture-c-member-list][A] final member list=$members');
      throw _DriveError(
        "A's member list for group \"$groupIdA\" has memberCount="
        '${members.length} (<2); expected self + joined peer B',
      );
    }
    if (selfMembers.length != 1) {
      await _dumpGroupDiagnostics(a, reason: 'self-entry count != 1');
      print('[fixture-c-member-list][A] final member list=$members');
      throw _DriveError(
        "A's member list for group \"$groupIdA\" has "
        '${selfMembers.length} isSelf:true entries; expected EXACTLY 1 (A)',
      );
    }
    if (nonSelfMembers.isEmpty) {
      await _dumpGroupDiagnostics(a, reason: 'no non-self member');
      print('[fixture-c-member-list][A] final member list=$members');
      throw _DriveError(
        "A's member list for group \"$groupIdA\" has NO non-self member; "
        'expected B (NGC group pubkey ${bGroupPk.substring(0, 16)}...)',
      );
    }
    if (!bStillPresent) {
      await _dumpGroupDiagnostics(a, reason: 'resolved B not in final list');
      print('[fixture-c-member-list][A] final member list=$members');
      throw _DriveError(
        "A's member list for group \"$groupIdA\" no longer includes the "
        'resolved B group identity ${bGroupPk.substring(0, 16)}...',
      );
    }
    print(
      '[fixture-c-member-list] PASS A2 member list shows BOTH self and B '
      '(memberCount=${members.length}, self=1, nonSelf=${nonSelfMembers.length})',
    );

    print('[fixture-c-member-list] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-member-list] ERROR: ${e.message}');
    return 1;
  } finally {
    await a.dispose();
    await b.dispose();
  }
}

/// A 64-char hex string is the joinable NGC chat-id shape.
bool _isChatId(String id) {
  if (id.length != 64) return false;
  return RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(id);
}

/// Poll `driver`'s knownGroups until a NEW group id appears (one not in
/// `baseline`). Returns the added group id. The joiner keys the group by the
/// chat-id it joined with, but the native layer may surface a different id, so
/// we accept ANY newly-added entry. On timeout, dump knownGroups + group
/// conversations and throw.
Future<String> _waitForGroupAdded(
  _PairDriver driver, {
  required Set<String> baseline,
  required int timeoutSecs,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final now = await driver.knownGroups();
    final added = now.difference(baseline);
    if (added.isNotEmpty) {
      return added.first;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await _dumpGroupDiagnostics(driver, reason: 'group never added (join)');
  throw _DriveError(
    'observer ${driver.name} knownGroups never grew beyond baseline '
    '$baseline within ${timeoutSecs}s (B never became a member)',
  );
}

/// Poll `founder`'s member list for `groupId` until a NON-SELF member appears,
/// returning that member's userID — the NGC group-specific public key (the
/// friend pubkey never matches). A non-self member showing up PROVES the
/// founder's peer cache holds it. A's cache populates via the founder's
/// HandleGroupPeerJoin (enabled by the loopback bootstrap) OR via
/// HandleGroupMessageGroup on a received group message. The message roundtrip is
/// flaky, so when [nudgeJoiner]/[nudgeGroupId] are given we NUDGE with a B->A
/// group message each round (best-effort — delivery failures are ignored) and
/// treat the member list as the authoritative signal. On timeout, dump
/// diagnostics + the last member list and throw (the kept loud-failure
/// diagnostic — NGC two-process peer connectivity is the residual).
Future<String> _waitForOtherMember(
  _PairDriver founder, {
  required String groupId,
  required int timeoutSecs,
  _PairDriver? nudgeJoiner,
  String? nudgeGroupId,
  String nonce = '',
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  var round = 0;
  List<Map<String, Object?>> last = const <Map<String, Object?>>[];
  while (DateTime.now().isBefore(deadline)) {
    round++;
    // Best-effort nudge so A can cache the joiner via a received group message
    // if the founder's peer-join hasn't fired; the poll below is authoritative.
    if (nudgeJoiner != null && nudgeGroupId != null) {
      try {
        await nudgeJoiner.sendGroupText(
          nudgeGroupId,
          'S36 nudge r$round $nonce',
        );
      } catch (_) {
        // delivery is the flaky leg — ignore
      }
    }
    try {
      last = await founder.groupMembers(groupId);
      for (final m in last) {
        final uid = (m['userID'] as String?) ?? '';
        if (m['isSelf'] != true && uid.isNotEmpty) {
          print(
            '[fixture-c-member-list] A resolved a non-self member '
            'on round $round',
          );
          return uid;
        }
      }
    } on _DriveError catch (e) {
      print(
        '[fixture-c-member-list][${founder.name}] member list pending: '
        '${e.message}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  await _dumpGroupDiagnostics(founder, reason: 'no non-self member in list');
  print('[fixture-c-member-list][${founder.name}] last member list=$last');
  throw _DriveError(
    'observer ${founder.name} never saw a non-self member in group "$groupId" '
    "within ${timeoutSecs}s (B never entered A's NGC peer cache — neither "
    'peer-join nor a received group message populated it)',
  );
}

/// Timeout diagnostics: knownGroups + each group-typed conversation.
Future<void> _dumpGroupDiagnostics(
  _PairDriver driver, {
  required String reason,
}) async {
  final base = await driver.dumpState();
  final known = (base['knownGroups'] as List?) ?? const <dynamic>[];
  print('[fixture-c-member-list][${driver.name}] timeout ($reason); '
      'knownGroups=$known');
  final convs = (base['conversations'] as List?) ?? const <dynamic>[];
  final groupConvs = <Map<String, Object?>>[
    for (final c in convs)
      if (c is Map && c['type'] == 2)
        {'conversationID': c['conversationID'], 'showName': c['showName']},
  ];
  print('[fixture-c-member-list][${driver.name}] group conversations='
      '$groupConvs');
}

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
}

/// The two ids l3_create_group returns: a LOCAL group id (creator's state key)
/// and the joinable 64-char hex chat-id.
class _CreatedGroup {
  _CreatedGroup({required this.groupId, required this.chatId});
  final String groupId;
  final String chatId;
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
    await d.waitForExtension('ext.mcp.toolkit.l3_join_group', timeoutSecs: 60);
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_group_member_list',
      timeoutSecs: 60,
    );
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_send_group_text',
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

  /// The SET of group ids this instance has joined, from base-dump
  /// `knownGroups`.
  Future<Set<String>> knownGroups() async {
    final state = await dumpState();
    final known = (state['knownGroups'] as List?) ?? const <dynamic>[];
    final out = <String>{};
    for (final g in known) {
      final id = g?.toString().trim() ?? '';
      if (id.isNotEmpty) out.add(id);
    }
    return out;
  }

  Future<void> ensureReady({required _FixtureAccount fixture}) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[fixture-c-member-list][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-member-list][$name] booting restored account '
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

  /// Create an NGC group (type: 'public' default | 'private'); returns the
  /// LOCAL group id and the chat-id (joinable only for public groups).
  Future<_CreatedGroup> createGroup({String? name, String? type}) async {
    final args = <String, Object?>{};
    if (name != null) args['name'] = name;
    if (type != null) args['type'] = type;
    final resp = await _call('ext.mcp.toolkit.l3_create_group', args);
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('[$name] l3_create_group failed: ${json['error']}');
    }
    final gid = (json['groupId']?.toString() ?? '').trim();
    final chatId = (json['chatId']?.toString() ?? '').trim();
    return _CreatedGroup(groupId: gid, chatId: chatId);
  }

  /// Join a public group by chat-id. NGC discovery can lag, so a join failure
  /// is retryable: try `attempts` times with `spacingMs` spacing.
  Future<void> joinGroupWithRetry(
    String groupId, {
    required int attempts,
    required int spacingMs,
  }) async {
    Object? lastErr;
    for (var i = 0; i < attempts; i++) {
      try {
        await joinGroup(groupId);
        return;
      } on _DriveError catch (e) {
        lastErr = e;
        print(
          '[fixture-c-member-list][$name] join attempt ${i + 1}/$attempts '
          'failed: ${e.message}',
        );
        if (i < attempts - 1) {
          await Future<void>.delayed(Duration(milliseconds: spacingMs));
        }
      }
    }
    throw _DriveError(
      '[$name] l3_join_group failed after $attempts attempts: '
      '${lastErr is _DriveError ? lastErr.message : lastErr}',
    );
  }

  Future<void> joinGroup(String groupId) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_join_group',
      <String, Object?>{'groupId': groupId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError('l3_join_group failed: ${json['error']}');
    }
  }

  /// Send a group text via a group id THIS side actually knows (creator: local
  /// id; joiner: chat-id). Surfaces {ok:false,error,detail} send failures.
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

  /// This instance's view of `groupId`'s members via l3_group_member_list. Each
  /// entry is {userID, role, isSelf}; for a REMOTE member, userID is its NGC
  /// group-specific public key, while the self entry carries this account's
  /// global Tox pubkey. Throws on a tool error so the caller can keep polling
  /// while the group settles.
  Future<List<Map<String, Object?>>> groupMembers(String groupId) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_group_member_list',
      <String, Object?>{'groupId': groupId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    if (json['ok'] != true) {
      throw _DriveError(
        'l3_group_member_list failed: code=${json['code']} '
        'desc=${json['desc'] ?? json['error']}',
      );
    }
    final raw = (json['members'] as List?) ?? const <dynamic>[];
    return <Map<String, Object?>>[
      for (final m in raw)
        if (m is Map)
          {
            'userID': m['userID']?.toString() ?? '',
            'role': m['role'],
            'isSelf': m['isSelf'] == true,
          },
    ];
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
