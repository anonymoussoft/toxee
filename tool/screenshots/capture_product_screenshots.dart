// Product-screenshot pipeline driver (plan:
// docs/plans/2026-06-03-product-screenshots-and-landing-page.md).
//
// Orchestrates 4 already-LAUNCHED toxee instances (ShotA hero + ShotB/C/D
// partners — see capture.sh, which launches them via the mcp_test
// launch_toxee_instance.sh with a persistent self-contained seed root):
//   1. ensureReady   — first run registers the personas via
//                      l3_register_account (seed-account marker), reuse runs
//                      ride auto-login / l3_boot_existing_account;
//   2. doctor        — manifest vs live state; "manifest present but account
//                      not restored" is a hard failure pointing at --reset;
//   3. seed          — idempotent: friendships, private group + invites,
//                      scripted conversations (inbound photo, sender-side
//                      quoted reply, PDF), pin + mute;
//   4. freshen       — every run, BEFORE any conversation is opened, so
//                      C/D unread badges + "just now" timestamps exist;
//   5. scene walk    — real-UI navigation via flutter_skill + screenshots
//                      into the output dir (P0 hard-fail, P1 warn).
//
// The harness conventions (string args, retry/poll helpers, per-script
// duplication) intentionally mirror tool/mcp_test/drive_fixture_c_pair.dart.

// ignore_for_file: depend_on_referenced_packages, avoid_print

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import '../mcp_test/fixture_c_bootstrap.dart';
import 'seed_data.dart';

const _manifestSchemaVersion = 1;
const _windowW = 1280, _windowH = 800;

Future<void> main(List<String> args) async {
  exitCode = await _main(args);
}

Future<int> _main(List<String> args) async {
  String? seedRoot;
  String outDir = 'screenshot';
  var includeInCall = false;
  var p0Only = false;
  // Two-phase split (driven by capture.sh): seeding leaves live-session
  // artifacts in the conversation list (sender-side raw-key ghost rows +
  // live-path "[Custom]" bubbles — both NON-persisted; underlying
  // normalization bug noted in the plan run-notes), so capture.sh runs
  // --seed-only, RESTARTS ShotA, then runs --scenes-only against the fresh
  // boot, which renders exactly the persisted truth a real user would see.
  var seedOnly = false;
  var scenesOnly = false;
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--seed-root':
        seedRoot = args[++i];
      case '--out':
        outDir = args[++i];
      case '--include-incall':
        includeInCall = true;
      case '--p0-only':
        p0Only = true;
      case '--seed-only':
        seedOnly = true;
      case '--scenes-only':
        scenesOnly = true;
      default:
        stderr.writeln('unknown arg: ${args[i]}');
        return 64;
    }
  }
  if (seedRoot == null) {
    stderr.writeln(
      'usage: capture_product_screenshots.dart --seed-root <dir> '
      '[--out screenshot] [--include-incall] [--p0-only] '
      '[--seed-only | --scenes-only]',
    );
    return 64;
  }

  final out = Directory(outDir);
  await out.create(recursive: true);
  final mediaDir = Directory('$seedRoot/generated_media');

  final drivers = <String, _Shot>{};
  try {
    for (final p in allPersonas) {
      drivers[p.instance] = await _Shot.connect(p, seedRoot);
    }
    final a = drivers['ShotA']!,
        b = drivers['ShotB']!,
        c = drivers['ShotC']!,
        d = drivers['ShotD']!;

    // ── manifest + ready ────────────────────────────────────────────────
    final manifestFile = File('$seedRoot/seed_manifest.json');
    var manifest = await _Manifest.load(manifestFile);
    for (final s in drivers.values) {
      await s.ensureReady(manifest?.toxIdOf(s.persona.instance));
    }
    for (final s in drivers.values) {
      await s.waitForConnected(timeoutSecs: 90);
    }

    // ── doctor ──────────────────────────────────────────────────────────
    if (manifest != null) {
      final issues = await _doctor(manifest, drivers);
      if (issues.isNotEmpty) {
        stderr
          ..writeln('[doctor] seed state DRIFTED from manifest:')
          ..writeln(issues.map((e) => '  - $e').join('\n'))
          ..writeln(
            '[doctor] external state was likely wiped (e.g. the fixture-C '
            'harness clears the whole com.toxee.app defaults domain). '
            'Re-run with --reset to rebuild the seed from scratch.',
          );
        return 2;
      }
      print('[doctor] manifest matches live state — reusing seed');
    }

    // ── full-mesh local DHT (NGC + same-host reliability) ───────────────
    await wireFullMeshBootstrap([
      for (final s in drivers.values)
        BootstrapTarget(s.persona.instance, s.vm, s.isolateId),
    ]);

    // ── idempotent seed (skipped in --scenes-only) ──────────────────────
    if (!scenesOnly) {
      final photoPath = await ensureLakeTrailPng(mediaDir);
      final pdfPath = await ensureTripPlanPdf(mediaDir);

      await _pairFriends(a, b);
      await _pairFriends(a, c);
      await _pairFriends(a, d);

      await _seedConversationAB(a, b, photoPath: photoPath, pdfPath: pdfPath);
      await _seedSimpleConversation(a, c, conversationAC, minCount: 4);
      await _seedSimpleConversation(a, d, conversationAD, minCount: 3);
      final groupChatId = await _seedGroup(a, [b, c], manifest?.groupChatId);

      // Pin the group on the hero + mute Sofia (recv-opt demo).
      final groupConvA = await a.findGroupConversationId();
      if (groupConvA != null) {
        await a.l3('l3_set_pinned', {
          'conversationId': groupConvA,
          'pinned': 'true',
        });
      }
      await a.l3('l3_set_c2c_recv_opt', {'userId': c.toxId, 'opt': '1'});

      manifest = _Manifest(
        schemaVersion: _manifestSchemaVersion,
        seededAt: manifest?.seededAt ?? DateTime.now().toIso8601String(),
        toxIds: {for (final s in drivers.values) s.persona.instance: s.toxId},
        groupChatId: groupChatId,
      );
      await manifest.save(manifestFile);
    }
    if (seedOnly) {
      print('[seed] phase complete — capture.sh restarts ShotA for scenes');
      return 0;
    }

    // ── freshen (badges + fresh timestamps; BEFORE any conv is opened) ──
    // Line-level idempotent so reuse runs don't stack duplicate freshen
    // bubbles; on reuse the existing lines keep their (older) timestamps,
    // which reads naturally ("yesterday") in the conversation list.
    final activePeer = (await a.dumpState())['activePeerId']?.toString();
    if (activePeer != null && activePeer.isNotEmpty) {
      print(
        '[freshen] WARN ShotA already has an active conversation '
        '($activePeer) — unread badges for that peer will not accrue',
      );
    }
    for (final (peer, lines) in [(b, freshenB), (c, freshenC), (d, freshenD)]) {
      for (final line in lines) {
        if (!await a.hasInboundText(peer.toxId, line)) {
          await peer.sendText(a.toxId, line);
        }
      }
    }
    await a.waitForUnreadFrom(c.toxId, atLeast: 1, timeoutSecs: 60);
    await a.waitForUnreadFrom(d.toxId, atLeast: 1, timeoutSecs: 60);
    print('[freshen] unread badges confirmed for ShotC/ShotD');

    // ── scene walk ──────────────────────────────────────────────────────
    final shooter = _Shooter(out);
    await a.setWindowBounds(_windowW, _windowH);
    // Explicit light theme: a fresh profile defaults to ThemeMode.system,
    // so a dark-mode host would silently shoot every "light" scene dark.
    await a.l3('l3_set_setting', {'key': 'themeMode', 'value': 'light'});
    await a.waitMs(700);

    // P0 01/02 — conversations master-detail + hero chat.
    await a.tapKey('sidebar_chats_tab');
    final convB = await a.findC2cConversationId(b.toxId);
    await a.tapKey('conversation_list_item:$convB');
    await a.waitMs(2200); // chat pane render + thumbnails
    await shooter.shot(a, '01_conversations', p0: true);
    await shooter.shot(a, '02_chat_c2c', p0: true);

    // P0 03 — group chat.
    final groupConv = await a.findGroupConversationId();
    if (groupConv != null) {
      await a.tapKey('conversation_list_item:$groupConv');
      await a.waitMs(1800);
    }
    await shooter.shot(a, '03_chat_group', p0: true);

    // P0 04 — contacts.
    await a.tapKey('sidebar_contacts_tab');
    await a.waitMs(1200);
    await shooter.shot(a, '04_contacts', p0: true);

    // P0 06 — settings. Navigated from the clean contacts view (NO modal in
    // the way — runs 10-15 opened the profile modal first and its lingering
    // barrier swallowed this tab switch, shipping a settings shot identical
    // to contacts). NOTE: 'Auto Login' text is useless as a verify signal
    // because the IndexedStack keeps every tab's subtree mounted — the
    // shooter's byte-identical guard is the real check.
    await a.tapKey('sidebar_settings_tab');
    await a.waitMs(1300);
    await shooter.shot(a, '06_settings', p0: true);

    // P0 05 — self profile + QR (a MODAL). Opened LAST among the tab scenes
    // so its barrier can't intercept any later tab navigation; dismissed
    // before the theme section.
    await a.tapKey('sidebar_user_avatar');
    await a.waitMs(1500);
    await shooter.shot(a, '05_profile_qr', p0: true);
    await a.tapAt(640, 720); // barrier tap dismisses the dialog
    await a.waitMs(700);

    // P0 07/08 — dark theme (shared applier keeps UIKit in sync).
    await a.l3('l3_set_setting', {'key': 'themeMode', 'value': 'dark'});
    await a.waitMs(900);
    await a.tapKey('sidebar_chats_tab');
    await a.waitMs(900);
    await shooter.shot(a, '07_dark_conversations', p0: true);
    await shooter.shot(a, '08_dark_chat', p0: true);
    await a.l3('l3_set_setting', {'key': 'themeMode', 'value': 'light'});
    await a.waitMs(900);

    if (!p0Only) {
      // P1 09/10 — ringing-state call shots (no mic capture until accept).
      // The FIRST invite of a session can race the callee's lazy
      // TUICallKitAdapter init (observed: adapter "Service initialized" in
      // the same second the invite landed, no ringing state) — so the scene
      // attempts twice: attempt #1 warms the adapter, attempt #2 rings.
      try {
        await b.setWindowBounds(_windowW, _windowH);
        var ringing = false;
        for (var attempt = 1; attempt <= 2 && !ringing; attempt++) {
          await b.l3('l3_start_call', {'userId': a.toxId});
          ringing = await a.waitForCallState('ringing', timeoutSecs: 20);
          if (!ringing) {
            print(
              '[scene] call attempt $attempt: no ringing '
              '(A call.state=${await a.callState()}) — '
              '${attempt == 1 ? "retrying after adapter warm-up" : "giving up"}',
            );
            await b.l3('l3_call_action', {'action': 'hangup'}, lenient: true);
            await a.waitMs(2500);
          }
        }
        if (!ringing) throw _DriveError('incoming call never reached ringing');
        final btn = await a.waitKey('call_accept_button', timeoutSecs: 10);
        if (!btn) {
          throw _DriveError(
            'ringing state reached but IncomingCallView never rendered',
          );
        }
        await shooter.shot(b, '10_outgoing_call', p0: false);
        await shooter.shot(a, '09_incoming_call', p0: false);
        if (includeInCall) {
          await a.l3('l3_call_action', {'action': 'accept'});
          await a.waitMs(2500);
          await shooter.shot(a, '15_in_call', p0: false);
          await a.l3('l3_call_action', {'action': 'hangup'});
        } else {
          await a.l3('l3_call_action', {'action': 'reject'});
        }
        await a.waitMs(1500); // overlay teardown
      } catch (e) {
        shooter.warn('call scenes (09/10) skipped: $e');
        // Best-effort cleanup so a half-open call can't bleed into later scenes.
        try {
          await a.l3('l3_call_action', {'action': 'reject'}, lenient: true);
        } catch (_) {}
        try {
          await b.l3('l3_call_action', {'action': 'hangup'}, lenient: true);
        } catch (_) {}
        await a.waitMs(1500);
      }

      // P1 11 — zh locale.
      try {
        await a.l3('l3_set_setting', {'key': 'languageCode', 'value': 'zh'});
        await a.waitMs(900);
        await a.tapKey('sidebar_chats_tab');
        await a.waitMs(700);
        await shooter.shot(a, '11_locale_zh', p0: false);
      } catch (e) {
        shooter.warn('zh locale scene (11) skipped: $e');
      } finally {
        await a.l3('l3_set_setting', {'key': 'languageCode', 'value': 'en'});
        await a.waitMs(700);
      }

      // (No Applications/IRC scene: the sidebar entry is disabled
      // product-wide — `const _showApplicationsEntry = false` in
      // lib/ui/settings/sidebar.dart — so there is nothing to capture.)

      // P1 12 — message search, driven through the visible conversation-list
      // header "Search" box. NOT the keyboard shortcut: the app binds
      // Cmd+Ctrl+F, which macOS consumes as the system fullscreen shortcut
      // before Flutter ever sees it (latent app bug, noted for follow-up).
      var searchPushedRoute = false;
      try {
        await a.foreground();
        await a.tapKey('sidebar_chats_tab');
        await a.waitMs(500);
        final r = await a.skill('tap', {'text': 'Search'});
        if (r['success'] != true) {
          throw _DriveError('header Search box not found');
        }
        searchPushedRoute =
            await a.waitKey('message_search_field', timeoutSecs: 8);
        if (searchPushedRoute) {
          // CustomSearch route: focus its field and type the query.
          await a.tapKey('message_search_field');
          await a.waitMs(300);
        }
        await a.skill('enterText', {'text': searchQuery});
        await a.waitMs(1800);
        await shooter.shot(a, '12_search', p0: false);
      } catch (e) {
        shooter.warn('search scene (12) skipped: $e');
      } finally {
        if (searchPushedRoute) {
          // Pop the search route via the top-left back affordance with
          // tapAt (NOT tapKey — route-popping buttons double-fire under the
          // synthetic tap path; flutter_skill double-tap hazard).
          await a.tapAt(28, 46);
        } else {
          await a.osaEscape(); // clear inline search focus/box
        }
        await a.waitMs(600);
      }
    }

    // Leave the app in a friendly state for the next (reuse) run.
    try {
      await a.tapKey('sidebar_chats_tab', retries: 2);
    } on _DriveError {
      await a.osaEscape();
      await a.waitMs(500);
      await a.tapKey('sidebar_chats_tab', retries: 2);
    }

    return shooter.summarize() ? 0 : 1;
  } on _DriveError catch (e) {
    stderr.writeln('[capture] ERROR: ${e.message}');
    return 1;
  } finally {
    for (final s in drivers.values) {
      await s.dispose();
    }
  }
}

// ───────────────────────────── seeding ──────────────────────────────────

Future<void> _pairFriends(_Shot a, _Shot peer) async {
  if (await a.hasFriend(peer.toxId)) {
    print('[seed] ${a.name}↔${peer.name} already friends');
    return;
  }
  print('[seed] pairing ${a.name}↔${peer.name}');
  await peer.l3('l3_add_friend_request', {'userId': a.toxId}, lenient: true);
  await a.waitForFriendApplication(peer.toxId, timeoutSecs: 120);
  await _retry(
    () => a.l3('l3_accept_friend_request', {'userId': peer.toxId}),
    attempts: 20,
    intervalMs: 1000,
    label: '${a.name} accept ${peer.name}',
  );
  await a.waitForFriendOnline(peer.toxId, timeoutSecs: 120);
  await peer.waitForFriendOnline(a.toxId, timeoutSecs: 120);
}

/// Seed the hero conversation with its media beats. Idempotency is
/// count-based: the full script is ~12 texts + reply + 2 files ⇒ skip when
/// the history already holds ≥ 14 messages.
Future<void> _seedConversationAB(
  _Shot a,
  _Shot b, {
  required String photoPath,
  required String pdfPath,
}) async {
  final existing = await a.messageCountWith(b.toxId);
  if (existing >= conversationABSeededCount) {
    print('[seed] A↔B conversation already seeded ($existing msgs)');
    return;
  }
  print('[seed] scripting A↔B conversation');
  // Friend links can go stale between pairing and scripting (4 instances +
  // DHT churn) — re-confirm both directions right before sending.
  await a.waitForFriendOnline(b.toxId, timeoutSecs: 120);
  await b.waitForFriendOnline(a.toxId, timeoutSecs: 120);
  for (final line in conversationAB) {
    final from = line.fromA ? a : b;
    final to = line.fromA ? b : a;
    // Line-level idempotency: a resumed run (or a late-delivered flake)
    // must not duplicate a bubble.
    if (!await to.hasInboundText(from.toxId, line.text)) {
      await from.sendText(to.toxId, line.text);
      await to.waitForInboundText(from.toxId, line.text, timeoutSecs: 120);
    }
    if (!line.fromA &&
        line.text == bReplyAnchor &&
        !await b.hasInboundText(a.toxId, aQuotedReply)) {
      // Sender-side quote (plan F14): ShotA replies, quoting B's line.
      await a.l3('l3_reply_text', {
        'userId': b.toxId,
        'text': aQuotedReply,
        'replyToText': bReplyAnchor,
      });
      await b.waitForInboundText(a.toxId, aQuotedReply, timeoutSecs: 120);
    }
    if (!line.fromA &&
        line.text == bPhotoLeadIn &&
        !await a.hasFileFrom(b.toxId, 'lake-trail.png')) {
      // Inbound photo → image bubble on ShotA (extension-classified).
      // contentB64: the host-generated bytes can't be READ by the sandboxed
      // app via filePath; the app decodes + writes its own temp source.
      await b.l3('l3_send_file', {
        'userId': a.toxId,
        'contentB64': base64Encode(await File(photoPath).readAsBytes()),
        'fileName': 'lake-trail.png',
      });
      await a.waitForFileFrom(b.toxId, 'lake-trail.png', timeoutSecs: 120);
    }
    if (line.fromA &&
        line.text.startsWith('Okay WOW') &&
        !await a.hasFileFrom(b.toxId, 'Trip-Plan.pdf')) {
      await b.l3('l3_send_file', {
        'userId': a.toxId,
        'contentB64': base64Encode(await File(pdfPath).readAsBytes()),
        'fileName': 'Trip-Plan.pdf',
      });
      await a.waitForFileFrom(b.toxId, 'Trip-Plan.pdf', timeoutSecs: 120);
    }
  }
}

Future<void> _seedSimpleConversation(
  _Shot a,
  _Shot peer,
  List<ScriptLine> script, {
  required int minCount,
}) async {
  final existing = await a.messageCountWith(peer.toxId);
  if (existing >= minCount) {
    print('[seed] A↔${peer.name} already seeded ($existing msgs)');
    return;
  }
  print('[seed] scripting A↔${peer.name} conversation');
  await a.waitForFriendOnline(peer.toxId, timeoutSecs: 120);
  await peer.waitForFriendOnline(a.toxId, timeoutSecs: 120);
  for (final line in script) {
    final from = line.fromA ? a : peer;
    final to = line.fromA ? peer : a;
    if (await to.hasInboundText(from.toxId, line.text)) continue;
    await from.sendText(to.toxId, line.text);
    await to.waitForInboundText(from.toxId, line.text, timeoutSecs: 120);
  }
}

/// Create the group on ShotA and seed a multi-sender history.
///
/// The group exists ONLY on ShotA: A's own lines go through the real
/// l3_send_group_text path; member lines are INJECTED on A via
/// l3_inject_group_text — the real FfiChatService ingestion seam, i.e. the
/// exact dedup/history/unread/stream pipeline native NGC delivery drives.
/// Rationale (run-validated): same-host NGC peer links are a per-pair coin
/// flip (NAT-hairpin announces) — runs showed one member connecting and
/// another never connecting through 3 minutes of S37-style nudging. C2C is
/// reliable; group transport isn't, and a screenshot needs the VIEW, which
/// is persistence + render — identical through the seam. (Supersedes the
/// plan-F8 private+invite choice; recorded in the run notes.)
Future<String?> _seedGroup(
  _Shot a,
  List<_Shot> members,
  String? manifestChatId,
) async {
  var convId = await a.findGroupConversationId();
  String groupIdA;
  if (convId == null) {
    print('[seed] creating group "$groupName" on ShotA');
    final created = await a.l3('l3_create_group', {
      'name': groupName,
      'type': 'public',
    });
    groupIdA = created['groupId']?.toString() ?? '';
    manifestChatId = created['chatId']?.toString();
    if (groupIdA.isEmpty) {
      throw _DriveError('l3_create_group returned no ids: $created');
    }
    convId = 'group_$groupIdA';
  } else {
    groupIdA = convId.substring('group_'.length);
    print('[seed] group "$groupName" already exists ($convId)');
  }

  // Group chatter — line-level idempotent against A's history.
  final history = await a.groupMessageCount(groupIdA);
  if (history < groupScript.length) {
    print('[seed] scripting group conversation (send + inject seam)');
    final memberByInstance = {
      for (final m in members) m.persona.instance: m,
    };
    for (final (instance, text) in groupScript) {
      if (await a.groupHistoryContains(groupIdA, text)) continue;
      if (instance == 'ShotA') {
        await a.l3('l3_send_group_text', {'groupId': groupIdA, 'text': text});
      } else {
        // Main pubkey as sender → the UI resolves the display name from the
        // friend list (NGC group-specific keys would render as raw hex).
        final m = memberByInstance[instance]!;
        await a.l3('l3_inject_group_text', {
          'groupId': groupIdA,
          'fromUserId': _pubkey(m.toxId),
          'text': text,
        });
      }
      // Keep visible timestamp order stable.
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
  } else {
    print('[seed] group conversation already seeded ($history msgs)');
  }
  return manifestChatId;
}

Future<List<String>> _doctor(
  _Manifest manifest,
  Map<String, _Shot> drivers,
) async {
  final issues = <String>[];
  for (final s in drivers.values) {
    final want = manifest.toxIdOf(s.persona.instance);
    if (want == null) {
      issues.add('${s.persona.instance}: missing from manifest');
      continue;
    }
    if (_pubkey(s.toxId) != _pubkey(want)) {
      issues.add(
        '${s.persona.instance}: live account ${_short(s.toxId)} != manifest '
        '${_short(want)} (account not restored?)',
      );
    }
  }
  final a = drivers['ShotA']!;
  for (final peer in ['ShotB', 'ShotC', 'ShotD']) {
    final want = manifest.toxIdOf(peer);
    if (want != null && !await a.hasFriend(want)) {
      issues.add('ShotA: friend $peer missing');
    }
  }
  return issues;
}

// ───────────────────────────── shooter ──────────────────────────────────

class _Shooter {
  _Shooter(this.outDir);
  final Directory outDir;
  final List<String> _ok = [];
  final List<String> _failedP0 = [];
  final List<String> _warned = [];
  // Byte-level frame fingerprints of prior scenes: a NEW scene that exactly
  // matches a DIFFERENT prior scene means navigation silently didn't take
  // (e.g. taps swallowed by a modal barrier) — surface it loudly. 01/02 and
  // 07/08 are intentional same-frame pairs.
  final Map<String, String> _frameOwners = {};
  static const _intentionalTwins = {
    '02_chat_c2c': '01_conversations',
    '08_dark_chat': '07_dark_conversations',
  };

  Future<void> shot(_Shot s, String sceneName, {required bool p0}) async {
    final path = '${outDir.path}/$sceneName.png';
    for (var attempt = 1; attempt <= 3; attempt++) {
      await s.foreground();
      await s.waitMs(350);
      final r = await s.skill('screenshot', const {});
      final b64 = r['image'] as String?;
      if (b64 != null && b64.isNotEmpty) {
        final bytes = base64Decode(b64);
        await File(path).writeAsBytes(bytes);
        final dims = _pngDims(bytes);
        final fp = '${bytes.length}:${bytes.fold<int>(0, (h, b) => (h * 31 + b) & 0x7fffffff)}';
        final owner = _frameOwners[fp];
        if (owner != null && _intentionalTwins[sceneName] != owner) {
          warn(
            '$sceneName is byte-identical to $owner — navigation likely '
            'did not take effect',
          );
        }
        _frameOwners.putIfAbsent(fp, () => sceneName);
        print(
          '[shot] $sceneName.png ${dims ?? "?x?"} '
          '(${(bytes.length / 1024).round()} KB)',
        );
        _ok.add(sceneName);
        return;
      }
      print('[shot] $sceneName attempt $attempt empty (window backgrounded?)');
      await s.waitMs(700);
    }
    if (p0) {
      _failedP0.add(sceneName);
      stderr.writeln('[shot] P0 FAILED: $sceneName');
    } else {
      warn('P1 scene $sceneName produced no image');
    }
  }

  void warn(String msg) {
    _warned.add(msg);
    print('[shot] WARN $msg');
  }

  /// Prints the run summary; returns true when all P0 scenes captured.
  bool summarize() {
    print('\n── capture summary ──');
    print('ok      : ${_ok.join(", ")}');
    if (_warned.isNotEmpty) print('warned  : ${_warned.join("; ")}');
    if (_failedP0.isNotEmpty) {
      stderr.writeln('P0 FAIL : ${_failedP0.join(", ")}');
      return false;
    }
    return true;
  }
}

/// Width×height from a PNG IHDR (bytes 16-23), or null if not a PNG.
String? _pngDims(List<int> bytes) {
  if (bytes.length < 24 || bytes[1] != 0x50) return null;
  int be(int o) =>
      (bytes[o] << 24) | (bytes[o + 1] << 16) | (bytes[o + 2] << 8) | bytes[o + 3];
  return '${be(16)}x${be(20)}';
}

// ───────────────────────────── instance driver ──────────────────────────

class _Shot {
  _Shot(this.persona, this.vm, this.isolateId, this.pid, this.wsUri);

  final Persona persona;
  VmService vm;
  String isolateId;
  final int pid;
  final String wsUri;
  String toxId = '';

  String get name => persona.instance;

  static Future<_Shot> connect(Persona persona, String seedRoot) async {
    final jsonFile = File('$seedRoot/${persona.instance}/instance.json');
    if (!await jsonFile.exists()) {
      throw _DriveError(
        '${persona.instance}: ${jsonFile.path} missing — launch instances '
        'via capture.sh',
      );
    }
    final info =
        jsonDecode(await jsonFile.readAsString()) as Map<String, dynamic>;
    final wsUri = info['ws_uri']?.toString() ?? '';
    final pid = (info['pid'] as num?)?.toInt() ?? 0;
    if (wsUri.isEmpty || pid == 0) {
      throw _DriveError('${persona.instance}: bad instance.json ($info)');
    }
    final vm = await vmServiceConnectUri(wsUri);
    final isolateId = await _findMainIsolate(vm);
    final s = _Shot(persona, vm, isolateId, pid, wsUri);
    for (final ext in [
      'ext.mcp.toolkit.l3_dump_state',
      'ext.mcp.toolkit.l3_register_account',
      'ext.flutter.flutter_skill.tap',
      'ext.flutter.flutter_skill.screenshot',
      ...fixtureCBootstrapExtensions,
    ]) {
      await s.waitForExtension(ext, timeoutSecs: 90);
    }
    return s;
  }

  Future<void> dispose() => vm.dispose();

  /// The VM-service websocket occasionally drops mid-run while the app stays
  /// healthy (observed after heavy traffic; macOS backgrounded-window
  /// throttling is the suspect). The app is never relaunched mid-run, so the
  /// recorded ws URI stays valid — reconnect + re-resolve the isolate.
  Future<void> _reconnect() async {
    print('[$name] VM service connection dropped — reconnecting $wsUri');
    try {
      await vm.dispose();
    } catch (_) {}
    vm = await vmServiceConnectUri(wsUri);
    isolateId = await _findMainIsolate(vm);
  }

  bool _isDisposedError(Object e) {
    final s = '$e';
    return s.contains('disposed') ||
        s.contains('WebSocket') ||
        s.contains('Connection closed');
  }

  Future<void> waitForExtension(String ext, {required int timeoutSecs}) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      final iso = await vm.getIsolate(isolateId);
      if ((iso.extensionRPCs ?? const <String>[]).contains(ext)) return;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _DriveError('[$name] extension $ext never registered');
  }

  Future<Map<String, dynamic>> _raw(
    String method,
    Map<String, Object?> args,
  ) async {
    final stringArgs = <String, String>{
      for (final e in args.entries) e.key: e.value.toString(),
    };
    Future<Map<String, dynamic>> once() async {
      final resp = await vm.callServiceExtension(
        method,
        isolateId: isolateId,
        args: stringArgs,
      );
      return (resp.json ?? const <String, dynamic>{}).cast<String, dynamic>();
    }

    try {
      return await once();
    } catch (e) {
      if (!_isDisposedError(e)) rethrow;
      await _reconnect();
      return once();
    }
  }

  /// L3 call; throws on {ok:false} unless [lenient] (e.g. "already sent").
  Future<Map<String, dynamic>> l3(
    String tool,
    Map<String, Object?> args, {
    bool lenient = false,
  }) async {
    final r = await _raw('ext.mcp.toolkit.$tool', args);
    if (r['ok'] != true && !lenient) {
      throw _DriveError('[$name] $tool failed: $r');
    }
    return r;
  }

  Future<Map<String, dynamic>> skill(
    String method, [
    Map<String, Object?> args = const {},
  ]) =>
      _raw('ext.flutter.flutter_skill.$method', args);

  Future<Map<String, dynamic>> dumpState({String? userId}) => _raw(
        'ext.mcp.toolkit.l3_dump_state',
        userId == null ? const {} : {'userId': userId},
      );

  // ── lifecycle ──

  Future<void> ensureReady(String? manifestToxId) async {
    final before = await dumpState();
    if (before['sessionReady'] == true) {
      print('[$name] session already ready (auto-login)');
    } else if (manifestToxId != null) {
      print('[$name] booting manifest account ${_short(manifestToxId)}');
      await l3('l3_boot_existing_account', {
        'toxId': manifestToxId,
        'nickname': persona.nickname,
        'statusMessage': persona.statusMessage,
      });
      await _waitSessionReady();
    } else {
      print('[$name] registering persona "${persona.nickname}"');
      await l3('l3_register_account', {
        'nickname': persona.nickname,
        'statusMessage': persona.statusMessage,
      });
      await _waitSessionReady();
    }
    final st = await dumpState();
    toxId = st['currentAccountToxId']?.toString() ?? '';
    if (toxId.isEmpty) {
      throw _DriveError('[$name] no currentAccountToxId after ready');
    }
    print('[$name] ready as ${persona.nickname} (${_short(toxId)})');
  }

  Future<void> _waitSessionReady() => _retry(
        () async {
          final s = await dumpState();
          if (s['sessionReady'] != true) {
            throw _DriveError('sessionReady still false');
          }
        },
        attempts: 90,
        intervalMs: 1000,
        label: '[$name] wait sessionReady',
      );

  Future<void> waitForConnected({required int timeoutSecs}) => _retry(
        () async {
          final s = await dumpState();
          if (s['isConnected'] != true) {
            throw _DriveError('not connected');
          }
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait DHT connected',
      );

  // ── data-layer queries ──

  Future<bool> hasFriend(String peerToxId) async {
    final st = await dumpState();
    final friends = (st['friends'] as List?) ?? const [];
    final want = _pubkey(peerToxId);
    return friends.any(
      (f) => f is Map && _pubkey(f['userId']?.toString() ?? '') == want,
    );
  }

  Future<void> waitForFriendApplication(
    String fromToxId, {
    required int timeoutSecs,
  }) =>
      _retry(
        () async {
          final st = await dumpState();
          final apps = (st['friendApplications'] as List?) ?? const [];
          final want = _pubkey(fromToxId);
          final hit = apps.any(
            (e) => e is Map && _pubkey(e['userId']?.toString() ?? '') == want,
          );
          if (!hit) throw _DriveError('no application yet');
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait friend application ${_short(fromToxId)}',
      );

  Future<void> waitForFriendOnline(
    String peerToxId, {
    required int timeoutSecs,
  }) =>
      _retry(
        () async {
          final st = await dumpState();
          final friends = (st['friends'] as List?) ?? const [];
          final want = _pubkey(peerToxId);
          final online = friends.any(
            (f) =>
                f is Map &&
                _pubkey(f['userId']?.toString() ?? '') == want &&
                f['online'] == true,
          );
          if (!online) throw _DriveError('friend not online yet');
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait friend online ${_short(peerToxId)}',
      );

  Future<void> sendText(String toToxId, String text) async {
    await l3('l3_send_text', {'userId': toToxId, 'text': text});
  }

  Future<bool> hasInboundText(String fromToxId, String text) async {
    final st = await dumpState(userId: fromToxId);
    final msgs = (st['messages'] as List?) ?? const [];
    return msgs.any(
      (m) => m is Map && m['isSelf'] != true && m['text']?.toString() == text,
    );
  }

  Future<void> waitForInboundText(
    String fromToxId,
    String text, {
    required int timeoutSecs,
  }) =>
      _retry(
        () async {
          if (!await hasInboundText(fromToxId, text)) {
            throw _DriveError('inbound "$text" not delivered yet');
          }
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait inbound text',
      );

  Future<bool> hasFileFrom(String fromToxId, String fileName) async {
    final st = await dumpState(userId: fromToxId);
    final msgs = (st['messages'] as List?) ?? const [];
    return msgs.any((m) => m is Map && jsonEncode(m).contains(fileName));
  }

  Future<void> waitForFileFrom(
    String fromToxId,
    String fileName, {
    required int timeoutSecs,
  }) =>
      _retry(
        () async {
          final st = await dumpState(userId: fromToxId);
          final msgs = (st['messages'] as List?) ?? const [];
          final hit = msgs.any(
            (m) => m is Map && jsonEncode(m).contains(fileName),
          );
          if (!hit) throw _DriveError('file $fileName not delivered yet');
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait file $fileName',
      );

  Future<int> messageCountWith(String peerToxId) async {
    final st = await dumpState(userId: peerToxId);
    return ((st['messages'] as List?) ?? const []).length;
  }

  Future<String?> findC2cConversationId(String peerToxId) async {
    final st = await dumpState();
    final convs = (st['conversations'] as List?) ?? const [];
    final want = _pubkey(peerToxId);
    for (final c in convs) {
      if (c is! Map) continue;
      final id = c['conversationID']?.toString() ?? '';
      if (id.startsWith('c2c_') && _pubkey(id.substring(4)) == want) return id;
    }
    // Conversation rows appear after first message; fall back to the
    // canonical id shape so the tile key still resolves.
    return 'c2c_$peerToxId';
  }

  Future<String?> findGroupConversationId() async {
    final st = await dumpState();
    final convs = (st['conversations'] as List?) ?? const [];
    for (final c in convs) {
      if (c is! Map) continue;
      final id = c['conversationID']?.toString() ?? '';
      if (id.startsWith('group_') &&
          c['showName']?.toString() == groupName) {
        return id;
      }
    }
    return null;
  }

  Future<int> groupMessageCount(String gid) async {
    final st = await _raw('ext.mcp.toolkit.l3_dump_state', {
      'conversationId': 'group_$gid',
    });
    return ((st['messages'] as List?) ?? const []).length;
  }

  Future<bool> groupHistoryContains(String gid, String text) async {
    final st = await _raw('ext.mcp.toolkit.l3_dump_state', {
      'conversationId': 'group_$gid',
    });
    final msgs = (st['messages'] as List?) ?? const [];
    return msgs.any((m) => m is Map && m['text']?.toString() == text);
  }


  Future<void> waitForUnreadFrom(
    String peerToxId, {
    required int atLeast,
    required int timeoutSecs,
  }) =>
      _retry(
        () async {
          final st = await dumpState();
          final convs = (st['conversations'] as List?) ?? const [];
          final want = _pubkey(peerToxId);
          for (final c in convs) {
            if (c is! Map) continue;
            final id = c['conversationID']?.toString() ?? '';
            if (id.startsWith('c2c_') && _pubkey(id.substring(4)) == want) {
              final unread = (c['unreadCount'] as num?)?.toInt() ?? 0;
              if (unread >= atLeast) return;
            }
          }
          throw _DriveError('unread < $atLeast');
        },
        attempts: timeoutSecs,
        intervalMs: 1000,
        label: '[$name] wait unread from ${_short(peerToxId)}',
      );

  Future<String> callState() async {
    final st = await dumpState();
    final call = st['call'];
    return call is Map ? (call['state']?.toString() ?? 'unknown') : 'none';
  }

  Future<bool> waitForCallState(
    String wanted, {
    required int timeoutSecs,
  }) async {
    final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
    while (DateTime.now().isBefore(deadline)) {
      if ((await callState()).toLowerCase() == wanted.toLowerCase()) {
        return true;
      }
      await waitMs(800);
    }
    return false;
  }

  // ── UI driving ──

  Future<void> foreground() async {
    final r = await Process.run('osascript', [
      '-e',
      'tell application "System Events" to set frontmost of '
          '(first process whose unix id is $pid) to true',
    ]);
    if (r.exitCode != 0) {
      print('[$name] WARN foreground failed: ${r.stderr}');
    }
    await waitMs(450);
  }

  Future<void> tapKey(String key, {int retries = 6}) async {
    for (var i = 0; i < retries; i++) {
      final r = await skill('tap', {'key': key});
      if (r['success'] == true) {
        await waitMs(350);
        return;
      }
      await waitMs(700);
    }
    throw _DriveError('[$name] tapKey "$key" failed after $retries tries');
  }

  Future<bool> waitKey(String key, {required int timeoutSecs}) async {
    final r = await skill('waitForElement', {
      'key': key,
      'timeout': '$timeoutSecs',
    });
    return r['found'] == true;
  }

  Future<void> setWindowBounds(int w, int h) async {
    await l3('l3_window_state', {
      'state': 'bounds',
      'width': '$w',
      'height': '$h',
    });
    await waitMs(400);
  }

  Future<void> tapAt(num x, num y) async {
    await skill('tapAt', {'x': '$x', 'y': '$y'});
    await waitMs(300);
  }

  Future<void> osaKeystroke(
    String key, {
    bool command = false,
    bool control = false,
  }) async {
    final mods = <String>[
      if (command) 'command down',
      if (control) 'control down',
    ];
    final using = mods.isEmpty ? '' : ' using {${mods.join(', ')}}';
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to keystroke "$key"$using',
    ]);
  }

  Future<void> osaEscape() async {
    await Process.run('osascript', [
      '-e',
      'tell application "System Events" to key code 53',
    ]);
  }

  Future<void> waitMs(int ms) =>
      Future<void>.delayed(Duration(milliseconds: ms));
}

// ───────────────────────────── manifest ─────────────────────────────────

class _Manifest {
  _Manifest({
    required this.schemaVersion,
    required this.seededAt,
    required this.toxIds,
    required this.groupChatId,
  });

  final int schemaVersion;
  final String seededAt;
  final Map<String, String> toxIds;
  final String? groupChatId;

  String? toxIdOf(String instance) => toxIds[instance];

  static Future<_Manifest?> load(File f) async {
    if (!await f.exists()) return null;
    try {
      final j = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      return _Manifest(
        schemaVersion: (j['schemaVersion'] as num?)?.toInt() ?? 0,
        seededAt: j['seededAt']?.toString() ?? '',
        toxIds: ((j['toxIds'] as Map?) ?? const {})
            .map((k, v) => MapEntry(k.toString(), v.toString())),
        groupChatId: j['groupChatId']?.toString(),
      );
    } catch (e) {
      stderr.writeln('[manifest] unreadable (${f.path}): $e — treating as none');
      return null;
    }
  }

  Future<void> save(File f) async {
    await f.writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'schemaVersion': schemaVersion,
        'seededAt': seededAt,
        'toxIds': toxIds,
        'groupChatId': groupChatId,
      }),
    );
    print('[manifest] saved ${f.path}');
  }
}

// ───────────────────────────── helpers ──────────────────────────────────

class _DriveError implements Exception {
  _DriveError(this.message);
  final String message;
  @override
  String toString() => message;
}

String _pubkey(String toxId) {
  final n = toxId.trim().toUpperCase();
  return n.length >= 64 ? n.substring(0, 64) : n;
}

String _short(String toxId) =>
    toxId.length > 16 ? '${toxId.substring(0, 16)}…' : toxId;

Future<String> _findMainIsolate(VmService vm) async {
  final deadline = DateTime.now().add(const Duration(seconds: 30));
  while (DateTime.now().isBefore(deadline)) {
    final v = await vm.getVM();
    final isolates = v.isolates ?? const <IsolateRef>[];
    if (isolates.isNotEmpty) {
      for (final iso in isolates) {
        if ((iso.name ?? '').toLowerCase().contains('main')) return iso.id!;
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
  Object? last;
  for (var i = 0; i < attempts; i++) {
    try {
      return await body();
    } catch (e) {
      last = e;
      await Future<void>.delayed(Duration(milliseconds: intervalMs));
    }
  }
  throw _DriveError('retry exhausted ($label): $last');
}
