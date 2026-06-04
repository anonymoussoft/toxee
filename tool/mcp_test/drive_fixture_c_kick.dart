// End-to-end driver for the S37 "group moderation — KICK leg" L3 scenario.
//
// This runs on the paired_for_e2e base where A and B are ALREADY friends and
// (after ensureReady) booted. A creates a PUBLIC NGC group; l3_create_group
// returns BOTH a LOCAL group id (e.g. "tox_1", used by the creator to key its
// own state) AND a separate 64-char hex `chatId` (the joinable public group
// id).
//
// B joins by that chat-id — the PROVEN S34 path — to get into the group
// reliably (no invite, which avoids the invite-delivery issue).
//
// KICK IDENTITY (the crux): NGC group members are identified by a PER-GROUP
// public key, NOT the friend/Tox pubkey. Kicking by toxB can therefore never
// resolve (root-caused live in session 6). So A RESOLVES B's group identity from
// its own member list (l3_group_member_list → C++ GetGroupMemberList), which
// returns each remote member's group pubkey, then kicks by that via the real
// SDK->C++ `tox_group_kick_peer` path.
//
// NGC PEER CONNECTIVITY (session 7 root cause + fix): live, the founder's
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
//
// Role-change (promote/demote) is out of scope — this leg is KICK only.
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
//   5. KICK: A: l3_kick_group_member(groupIdA, bGroupPk). Assert ok==true (else
//      print code+desc and FAIL) => PASS A2 (kick sent). Re-kick across short
//      rounds while polling B.knownGroups for removal (B-side propagation lag).
//   6. ASSERT removed: B.knownGroups NO LONGER contains the group => PASS A3.
//      On timeout print B.knownGroups + B.conversations(type==2).
//   7. Return 0 all-pass / 1 fail / 64 usage.
//
// CLI:
//   dart run tool/mcp_test/drive_fixture_c_kick.dart \
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
  // --private: create a PRIVATE NGC group + invite B over the friend link
  // (deterministic, no public-DHT discovery) instead of the default PUBLIC
  // group + chat-id join. Assertions switch to A-side (A's member list) because
  // an invite auto-join does not propagate to B's Dart knownGroups.
  var private = false;
  for (var i = 0; i < args.length; i++) {
    final arg = args[i];
    if (arg == '--fixture-manifest') {
      if (i + 1 >= args.length) {
        print('usage: --fixture-manifest requires a path');
        return 64;
      }
      fixtureManifestPath = args[++i];
    } else if (arg == '--private') {
      private = true;
    } else {
      positional.add(arg);
    }
  }
  if (positional.length < 2) {
    print(
      'usage: drive_fixture_c_kick.dart <ws_uri_A> <ws_uri_B> '
      '[--fixture-manifest path] [--private]',
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
      print('[fixture-c-kick] no manifest; assuming both sessions ready');
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
      '[fixture-c-kick] toxA=${toxA.substring(0, 16)}... '
      'toxB=${toxB.substring(0, 16)}...',
    );

    await a.waitForFriendOnline(userId: toxB, timeoutSecs: 120);
    await b.waitForFriendOnline(userId: toxA, timeoutSecs: 120);

    final nonce = DateTime.now().microsecondsSinceEpoch.toString();

    final String groupIdA;
    final String bGroupPk;
    String? joinedId; // PUBLIC path only: the group id B's knownGroups gained.

    if (private) {
      // ===== PRIVATE + INVITE (friend-link discovery; reliable same-host) =====
      final baseKnownBPriv = await b.knownGroups();
      // 2p. B must auto-accept group invites BEFORE the invite, else it won't
      // join. l3_set_setting drives the LIVE HomePage setter (cached flag + C++
      // sync), confirmed via dump_state before proceeding.
      await b.setSetting('autoAcceptGroupInvites', 'true');
      await b.waitForAutoAcceptGroupInvites(expected: true, timeoutSecs: 10);
      print('[fixture-c-kick] B autoAcceptGroupInvites=true confirmed');

      // 3p. A creates a PRIVATE NGC group (invite-only — peers connect over the
      // existing friend link, NOT the public DHT). No joinable chat-id.
      final created = await a.createGroup(
        name: 'l3_s37p_$nonce',
        type: 'private',
      );
      groupIdA = created.groupId;
      if (groupIdA.isEmpty) {
        throw _DriveError('create_group (private) returned an empty groupId');
      }
      print('[fixture-c-kick] created PRIVATE group localGroupId="$groupIdA"');

      // 4p. A freshly-created NGC group isn't connected yet, and
      // tox_group_invite_friend silently no-ops (returns ok locally but doesn't
      // transmit) while disconnected. Let it announce, then invite in a retry
      // loop — later attempts land once the group connects.
      await Future<void>.delayed(const Duration(seconds: 15));
      var invited = false;
      for (var attempt = 1; attempt <= 6 && !invited; attempt++) {
        final inv = await a.inviteToGroup(groupId: groupIdA, userId: toxB);
        print(
          '[fixture-c-kick] invite attempt $attempt '
          '(ok=${inv.ok} code=${inv.code} desc="${inv.desc}")',
        );
        if (inv.ok) {
          invited = true;
        } else {
          await Future<void>.delayed(const Duration(seconds: 5));
        }
      }
      if (!invited) {
        throw _DriveError('l3_invite_to_group never returned ok (send leg)');
      }
      print('[fixture-c-kick] PASS A1 invite-sent (PRIVATE)');

      // 5p. RESOLVE: A sees B once B auto-joins (the invite connects the peers
      // over the friend link, so A's HandleGroupPeerJoin fires). B has no local
      // group id to nudge from, so this is a pure member-list poll. A non-self
      // member's userID is B's per-group pubkey — the kickable identity.
      bGroupPk = await _waitForOtherMember(
        a,
        groupId: groupIdA,
        timeoutSecs: 120,
      );
      print(
        '[fixture-c-kick] A resolved B group identity '
        '${bGroupPk.substring(0, 16)}... (PRIVATE; NOT friend toxB '
        '${toxB.substring(0, 16)}...)',
      );
      // 6p. Verify the invite auto-join propagated to B's knownGroups (the
      // DartNotifyGroupJoin C++ fix). If it did, the kick asserts B-SIDE removal
      // (spec-complete, exercising the self-kick fix); else it falls back to the
      // A-side member-list check below.
      try {
        joinedId = await _waitForGroupAdded(
          b,
          baseline: baseKnownBPriv,
          timeoutSecs: 30,
        );
        print(
          '[fixture-c-kick] PRIVATE B-side: B.knownGroups gained "$joinedId" '
          '(invite auto-join propagated -> B-side A3)',
        );
      } catch (_) {
        print(
          '[fixture-c-kick] PRIVATE B-side: B.knownGroups did NOT gain the '
          'group within 30s -> A-side A3 fallback',
        );
      }
    } else {
      // ===== PUBLIC + JOIN (DHT discovery; the historical S37 flow) =====
      // 2. A creates the public NGC group: BOTH a LOCAL group id AND the joinable
      // 64-char hex chatId (what B joins with). Validate the chatId shape.
      final created = await a.createGroup(name: 'l3_s37_$nonce');
      groupIdA = created.groupId;
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
        '[fixture-c-kick] created group: localGroupId="$groupIdA" '
        'chatId=${chatId.substring(0, 16)}... (64-hex)',
      );

      // 3. B JOINS by chat-id (PROVEN S34 path; no invite). DHT discovery can
      // lag, so retry; confirm membership by watching B.knownGroups GROW.
      final baseKnownB = await b.knownGroups();
      print('[fixture-c-kick] B baseline knownGroups=$baseKnownB');
      await b.joinGroupWithRetry(chatId, attempts: 6, spacingMs: 3000);
      joinedId = await _waitForGroupAdded(
        b,
        baseline: baseKnownB,
        timeoutSecs: 90,
      );
      print('[fixture-c-kick] PASS A1 joined (B.knownGroups gained "$joinedId")');

      // 4+5. RESOLVE (robust nudge-and-poll). A's cache populates via peer-join
      // (bootstrap) OR HandleGroupMessageGroup on a received B->A message
      // (V2TIMManagerImpl.cpp:4893); the message roundtrip is flaky, so nudge
      // best-effort and treat A's member list as authoritative.
      bGroupPk = await _waitForOtherMember(
        a,
        groupId: groupIdA,
        nudgeJoiner: b,
        nudgeGroupId: chatId,
        nonce: nonce,
        timeoutSecs: 150,
      );
      print(
        '[fixture-c-kick] A resolved B group identity '
        '${bGroupPk.substring(0, 16)}... (NOT friend toxB '
        '${toxB.substring(0, 16)}...)',
      );
    }

    // 6. KICK B by its GROUP identity, then verify removal. Removal is checked
    // A-side (A's member list drops B) for PRIVATE — an invite auto-join does
    // NOT propagate to B's knownGroups — and B-side (B's knownGroups drops the
    // group, via the self-kick C++ fix) for PUBLIC. Re-kick across short rounds
    // (propagation can lag).
    var kicked = false;
    dynamic lastKick;
    for (var round = 1; round <= 6 && !kicked; round++) {
      lastKick = await a.kickGroupMember(groupId: groupIdA, userId: bGroupPk);
      print(
        '[fixture-c-kick] kick round $round (ok=${lastKick.ok} '
        'code=${lastKick.code} desc=${lastKick.desc})',
      );
      if (lastKick.ok != true) {
        break;
      }
      try {
        if (joinedId != null) {
          // B-SIDE removal: B's knownGroups drops the group (the self-kick C++
          // fix). Set for PUBLIC always, and for PRIVATE once the invite
          // auto-join propagated to B's knownGroups.
          await _waitForGroupRemoved(b, groupId: joinedId, timeoutSecs: 15);
        } else {
          // PRIVATE with no knownGroups propagation: assert A-SIDE (A's member
          // list drops B).
          await _waitForMemberGone(
            a,
            groupId: groupIdA,
            targetUid: bGroupPk,
            timeoutSecs: 15,
          );
        }
        kicked = true;
      } catch (_) {
        // kick accepted but removal not observed yet — re-kick.
      }
    }
    if (lastKick == null || lastKick.ok != true) {
      throw _DriveError(
        'l3_kick_group_member did not return ok kicking B by group identity '
        '${bGroupPk.substring(0, 16)}... '
        '(code=${lastKick?.code} desc=${lastKick?.desc})',
      );
    }
    print('[fixture-c-kick] PASS A2 kick-sent (code=${lastKick.code})');
    if (!kicked) {
      throw _DriveError(
        'kick resolved + sent for B group identity '
        '${bGroupPk.substring(0, 16)}... but B was not removed within the '
        'window (${joinedId != null ? "B-side kicked-event not propagating to "
            "knownGroups" : "A member list still shows B"})',
      );
    }
    print(
      '[fixture-c-kick] PASS A3 removed '
      '(${joinedId != null ? 'B.knownGroups lost "$joinedId"' : "A member "
          "list dropped B"})',
    );

    print('[fixture-c-kick] PASS');
    return 0;
  } on _DriveError catch (e) {
    print('[fixture-c-kick] ERROR: ${e.message}');
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
/// returning that member's userID — the NGC group-specific public key, which is
/// the identity KickGroupMember resolves (the friend pubkey never can). A
/// non-self member showing up PROVES the founder's peer cache holds it (the
/// kick's resolution precondition). A's cache populates via the founder's
/// HandleGroupPeerJoin (enabled by the loopback bootstrap) OR via
/// HandleGroupMessageGroup on a received group message. The message roundtrip is
/// flaky, so when [nudgeJoiner]/[nudgeGroupId] are given we NUDGE with a B->A
/// group message each round (best-effort — delivery failures are ignored) and
/// treat the member list as the authoritative signal. On timeout, dump
/// diagnostics + the last member list and throw.
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
          'S37 nudge r$round $nonce',
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
          print('[fixture-c-kick] A resolved a non-self member on round $round');
          return uid;
        }
      }
    } on _DriveError catch (e) {
      print(
        '[fixture-c-kick][${founder.name}] member list pending: ${e.message}',
      );
    }
    await Future<void>.delayed(const Duration(seconds: 3));
  }
  await _dumpGroupDiagnostics(founder, reason: 'no non-self member in list');
  print('[fixture-c-kick][${founder.name}] last member list=$last');
  throw _DriveError(
    'observer ${founder.name} never saw a non-self member in group "$groupId" '
    "within ${timeoutSecs}s (B not in A's NGC peer cache — neither peer-join nor "
    'a received group message populated it)',
  );
}

/// Poll `driver`'s knownGroups until `groupId` is NO LONGER present (B was
/// kicked => removed). On timeout, dump knownGroups + group conversations and
/// throw.
Future<void> _waitForGroupRemoved(
  _PairDriver driver, {
  required String groupId,
  required int timeoutSecs,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final now = await driver.knownGroups();
    if (!now.contains(groupId)) {
      return;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await _dumpGroupDiagnostics(driver, reason: 'group still present (kick)');
  throw _DriveError(
    'observer ${driver.name} still has group "$groupId" in knownGroups after '
    '${timeoutSecs}s (B was not removed by the kick)',
  );
}

/// PRIVATE-path A3: poll the founder's member list until `targetUid` (the kicked
/// member's group pubkey) is NO LONGER present — the moderator's own view
/// confirming the kick took effect. Used instead of B.knownGroups because an
/// invite auto-join doesn't propagate to B's Dart knownGroups. On timeout, dump
/// diagnostics and throw.
Future<void> _waitForMemberGone(
  _PairDriver founder, {
  required String groupId,
  required String targetUid,
  required int timeoutSecs,
}) async {
  final wantPk = targetUid.toLowerCase();
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    List<Map<String, Object?>> members;
    try {
      members = await founder.groupMembers(groupId);
    } on _DriveError {
      await Future<void>.delayed(const Duration(seconds: 1));
      continue;
    }
    final stillThere = members.any(
      (m) => ((m['userID'] as String?) ?? '').toLowerCase() == wantPk,
    );
    if (!stillThere) return;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  await _dumpGroupDiagnostics(founder, reason: 'member still in list (kick)');
  throw _DriveError(
    'founder ${founder.name} still lists member '
    '${targetUid.substring(0, 16)}... after ${timeoutSecs}s '
    '(kick did not remove B from the group)',
  );
}

/// Timeout diagnostics: knownGroups + each group-typed conversation.
Future<void> _dumpGroupDiagnostics(
  _PairDriver driver, {
  required String reason,
}) async {
  final base = await driver.dumpState();
  final known = (base['knownGroups'] as List?) ?? const <dynamic>[];
  print('[fixture-c-kick][${driver.name}] timeout ($reason); '
      'knownGroups=$known');
  final convs = (base['conversations'] as List?) ?? const <dynamic>[];
  final groupConvs = <Map<String, Object?>>[
    for (final c in convs)
      if (c is Map && c['type'] == 2)
        {'conversationID': c['conversationID'], 'showName': c['showName']},
  ];
  print('[fixture-c-kick][${driver.name}] group conversations='
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

/// Result of l3_kick_group_member: {ok, code, desc}.
class _KickResult {
  _KickResult({required this.ok, required this.code, required this.desc});
  final bool ok;
  final Object? code;
  final Object? desc;
}

/// Result of l3_invite_to_group: {ok, code, desc}.
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
    await d.waitForExtension('ext.mcp.toolkit.l3_join_group', timeoutSecs: 60);
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_kick_group_member',
      timeoutSecs: 60,
    );
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
    // PRIVATE-mode (--private) tools: invite over the friend link + the
    // autoAcceptGroupInvites toggle. Always registered, so waiting is harmless
    // for the default PUBLIC path too.
    await d.waitForExtension(
      'ext.mcp.toolkit.l3_invite_to_group',
      timeoutSecs: 60,
    );
    await d.waitForExtension('ext.mcp.toolkit.l3_set_setting', timeoutSecs: 60);
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
      print('[fixture-c-kick][$name] session already ready');
      return;
    }
    print(
      '[fixture-c-kick][$name] booting restored account '
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
          '[fixture-c-kick][$name] join attempt ${i + 1}/$attempts failed: '
          '${e.message}',
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

  /// Kick `userId` from `groupId` via the SDK group manager (reaches C++
  /// tox_group_kick_peer). Returns {ok, code, desc}; ok==true means code==0.
  Future<_KickResult> kickGroupMember({
    required String groupId,
    required String userId,
  }) async {
    final resp = await _call(
      'ext.mcp.toolkit.l3_kick_group_member',
      <String, Object?>{'groupId': groupId, 'userId': userId},
    );
    final json = (resp.json ?? const <String, dynamic>{})
        .cast<String, dynamic>();
    return _KickResult(
      ok: json['ok'] == true,
      code: json['code'],
      desc: json['desc'] ?? json['error'] ?? json['detail'],
    );
  }

  /// This instance's view of `groupId`'s members via l3_group_member_list. Each
  /// entry is {userID, role, isSelf}; for a REMOTE member, userID is its NGC
  /// group-specific public key (the identity KickGroupMember resolves), while
  /// the self entry carries this account's global Tox pubkey. Throws on a tool
  /// error so the caller can keep polling while the group settles.
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

  /// Invite a friend (by Tox id) to a group via l3_invite_to_group (reaches C++
  /// tox_group_invite_friend over the friend link). Returns {ok, code, desc}.
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
    final code = (json['code'] is num)
        ? (json['code'] as num).toInt()
        : int.tryParse(json['code']?.toString() ?? '') ?? -1;
    return _InviteResult(
      ok: json['ok'] == true,
      code: code,
      desc: json['desc']?.toString() ?? json['error']?.toString() ?? '',
    );
  }

  /// Drive a fixture-safe account setting via l3_set_setting (live applier).
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

  /// Wait until dump_state reports autoAcceptGroupInvites == [expected].
  Future<void> waitForAutoAcceptGroupInvites({
    required bool expected,
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final state = await dumpState();
      if (state['autoAcceptGroupInvites'] == expected) return;
      await Future<void>.delayed(const Duration(seconds: 1));
    }
    throw _DriveError('[$name] autoAcceptGroupInvites did not become $expected');
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
