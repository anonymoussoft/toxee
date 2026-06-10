// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

Future<int> runCustomMessage(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for custom_message: A=$toxA B=$toxB');
  }
  if (await areFriends(a, toxB) || await areFriends(b, toxA)) {
    throw DriveError('custom_message requires a no-friend pair');
  }
  final wording = 'S54-CUSTOM-${DateTime.now().microsecondsSinceEpoch}';
  await driveAddFriend(b, toxA, message: wording);
  final st = await a.waitState(
    (s) {
      final apps = (s['friendApplications'] as List?) ?? const [];
      return apps.any(
        (e) =>
            e is Map &&
            _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB) &&
            (e['wording']?.toString() ?? '') == wording,
      );
    },
    timeoutSecs: 120,
    label: 'friendApplication wording from B',
  );
  final apps = (st['friendApplications'] as List).cast<dynamic>();
  final app =
      apps.firstWhere(
            (e) =>
                e is Map &&
                _pubkey(e['userId']?.toString() ?? '') == _pubkey(toxB),
          )
          as Map;
  final seenWording = app['wording']?.toString() ?? '';
  if (seenWording != wording) {
    print('[pair] FAIL: custom message mismatch "$seenWording" != "$wording"');
    return 1;
  }
  await _refreshApplicationList(a, toxB, detail: false);
  final wordingKey = 'contact_application_addwording:${toxB.trim()}';
  await a.waitKey(wordingKey, timeoutSecs: 6);
  await driveRespondToApplication(a, toxB, accept: false);
  if (!await waitFriendshipState(
        a,
        b,
        toxA,
        toxB,
        friends: false,
        timeoutSecs: 20,
      ) &&
      (await areFriends(a, toxB) || await areFriends(b, toxA))) {
    print(
      '[pair] WARN: custom_message decline unexpectedly formed friendship; '
      'running reset_friendship cleanup',
    );
    final resetRc = await runResetFriendship(a, b, nickA, nickB);
    if (resetRc != 0 ||
        await areFriends(a, toxB) ||
        await areFriends(b, toxA)) {
      print(
        '[pair] FAIL: custom_message cleanup unexpectedly formed friendship',
      );
      return 1;
    }
  }
  // Leave the pair in a reusable no-friend shell so the next no-friend
  // scenario can continue the same launch without another recovery dance.
  await ensureContactsShell(a);
  await ensureNewEntryShell(b);
  // Let any late friend-application deletion callbacks from the just-refused
  // request settle before the next no-friend scenario re-sends to the same
  // peer. Without this pause we've seen the next request arrive in native
  // pending_applications_, then get cleared before l3_dump_state surfaces it.
  await Future<void>.delayed(const Duration(seconds: 4));
  print('[pair] PASS: custom message round-tripped and self-cleaned');
  return 0;
}

Future<String?> _callState(Inst inst) async {
  final s = await inst.dumpState();
  final call = (s['call'] as Map?)?.cast<String, dynamic>();
  return call?['state']?.toString();
}

Future<String?> _currentConversationId(Inst inst) async {
  final s = await inst.dumpState();
  final cur = (s['currentConversation'] as Map?)?.cast<String, dynamic>();
  return cur?['conversationID']?.toString();
}

Future<bool> _waitActiveChatPeerOnline(
  Inst inst, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final s = await inst.dumpState();
    if (s['activeChatPeerOnline'] == true) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<bool> _waitCallStateAny(
  Inst inst,
  Set<String> states, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final current = await _callState(inst);
    if (current != null && states.contains(current)) return true;
    await Future<void>.delayed(const Duration(seconds: 1));
  }
  return false;
}

Future<bool> _waitCallStateAnyForegrounded(
  Inst inst,
  Set<String> states, {
  int timeoutSecs = 30,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    await inst.foreground();
    final current = await _callState(inst);
    if (current != null && states.contains(current)) return true;
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  return false;
}

Future<bool> _startVoiceCallUntilRinging(
  Inst caller,
  Inst callee,
  String calleeId, {
  int attempts = 3,
  int timeoutSecs = 10,
}) async {
  final calleePubkey = _pubkey(calleeId);
  for (var attempt = 0; attempt < attempts; attempt++) {
    await openChat(
      caller,
      calleeId,
      preferConversationList: true,
      requirePeerOnline: true,
    );
    await _reopenChatFromConversationList(caller, 'c2c_$calleePubkey');
    await caller.foreground();
    await caller.tapKey('chat_call_voice_button');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    if (await _waitCallStateAnyForegrounded(callee, {
      'ringing',
      'incoming',
    }, timeoutSecs: timeoutSecs)) {
      return true;
    }
    final callerState = await _callState(caller);
    final calleeState = await _callState(callee);
    print(
      '[pair] WARN voice-call start retry '
      '(attempt ${attempt + 1}/$attempts '
      'callerState=$callerState calleeState=$calleeState)',
    );
    if (callerState == 'ringing' ||
        callerState == 'inCall' ||
        callerState == 'ended') {
      await caller.foreground();
      await caller.tryTapKey('call_hangup_button', retries: 2);
    }
    // Let both sides' call state settle back to idle before re-issuing the
    // next invite. The local notifier auto-resets ended -> idle after 2s, so a
    // too-fast retry can re-enter while the previous signaling call is still
    // winding down and never reach the callee.
    await _waitCallStateAny(caller, {'idle'}, timeoutSecs: 5);
    await _waitCallStateAny(callee, {'idle'}, timeoutSecs: 5);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    if (attempt + 1 < attempts) {
      print('[pair] retrying outgoing call after idle settle');
    }
  }
  return false;
}

Future<int> runCallVoice(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for call_voice: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] call_voice requires an existing friendship');
    return 1;
  }
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    await a.shot('/tmp/ui_call_reject_fail_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_call_reject_fail_B.png');
    print('[pair] FAIL: incoming call never reached ringing');
    print(
      '[pair] call_reject diag: '
      'A.call=${(aState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'B.call=${(bState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'A.activeChatPeerOnline=${aState['activeChatPeerOnline']} '
      'B.activeChatPeerOnline=${bState['activeChatPeerOnline']} '
      'A.currentConversation=${aState['currentConversation']} '
      'B.currentConversation=${bState['currentConversation']} '
      'A.homeShell=${aState['homeShell']} '
      'B.homeShell=${bState['homeShell']}',
    );
    return 1;
  }
  await a.foreground();
  await a.tapKey('call_accept_button');
  final inCallA = await _waitCallStateAny(a, {'inCall'});
  final inCallB = await _waitCallStateAny(b, {'inCall'});
  if (!inCallA || !inCallB) {
    print(
      '[pair] FAIL: call did not reach inCall '
      '(A=${await _callState(a)} B=${await _callState(b)})',
    );
    return 1;
  }
  await b.foreground();
  await b.tapKey('call_hangup_button');
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  await a.shot('/tmp/ui_call_voice_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_call_voice_B.png');
  if (endedA && endedB) {
    print('[pair] PASS: voice call accepted and hung up through real UI');
    return 0;
  }
  print(
    '[pair] FAIL: call did not tear down cleanly '
    '(A=${await _callState(a)} B=${await _callState(b)})',
  );
  return 1;
}

Future<int> runCallReject(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for call_reject: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    print('[pair] call_reject requires an existing friendship');
    return 1;
  }
  final ringing = await _startVoiceCallUntilRinging(b, a, toxA);
  if (!ringing) {
    final aState = await a.dumpState();
    final bState = await b.dumpState();
    await a.shot('/tmp/ui_call_reject_fail_A.png');
    await b.foreground();
    await b.shot('/tmp/ui_call_reject_fail_B.png');
    print('[pair] FAIL: incoming call never reached ringing');
    print(
      '[pair] call_reject diag: '
      'A.call=${(aState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'B.call=${(bState['call'] as Map?)?.cast<String, dynamic>()['state']} '
      'A.activeChatPeerOnline=${aState['activeChatPeerOnline']} '
      'B.activeChatPeerOnline=${bState['activeChatPeerOnline']} '
      'A.currentConversation=${aState['currentConversation']} '
      'B.currentConversation=${bState['currentConversation']} '
      'A.homeShell=${aState['homeShell']} '
      'B.homeShell=${bState['homeShell']}',
    );
    return 1;
  }
  await a.foreground();
  await a.tapKey('call_decline_button');
  final endedA = await _waitCallStateAny(a, {'ended', 'idle'});
  final endedB = await _waitCallStateAny(b, {'ended', 'idle'});
  await a.shot('/tmp/ui_call_reject_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_call_reject_B.png');
  if (endedA && endedB) {
    print('[pair] PASS: voice call rejected through real UI');
    return 0;
  }
  print(
    '[pair] FAIL: rejected call did not settle to idle '
    '(A=${await _callState(a)} B=${await _callState(b)})',
  );
  return 1;
}

// Logical-pixel center of the desktop composer text field (1280x768 window).
const _composerX = 830;
const _composerY = 702;

/// Open the C2C chat with [friendPubkey] (64-char) by tapping the contact tile.
Future<void> openChat(
  Inst inst,
  String friendId, {
  bool preferConversationList = true,
  bool requirePeerOnline = false,
}) async {
  await inst.foreground();
  final fullId = friendId.trim();
  final friendPubkey = _pubkey(friendId);
  final targetConversation = 'c2c_$friendPubkey';
  Future<bool> ready() async {
    if (!await _chatSurfaceReady(inst, targetConversation, timeoutSecs: 2)) {
      return false;
    }
    if (!requirePeerOnline) {
      return true;
    }
    return _waitActiveChatPeerOnline(inst, timeoutSecs: 3);
  }

  if (preferConversationList && await ready()) {
    return;
  }
  if (preferConversationList &&
      await _homeShellTab(inst) == 'chats' &&
      await _waitConversationListed(inst, targetConversation)) {
    await inst.tapKey('conversation_list_item:$targetConversation');
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    if (await ready()) {
      return;
    }
  }
  if (preferConversationList && await _homeShellTab(inst) != 'chats') {
    await returnToChatsHome(inst, rounds: 4);
    if (await _waitConversationListed(inst, targetConversation)) {
      await inst.tapKey('conversation_list_item:$targetConversation');
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (await ready()) {
        return;
      }
    }
  }
  if (preferConversationList) {
    final st = await inst.dumpState();
    final ids = (st['conversationIds'] as List?) ?? const [];
    print(
      '[${inst.name}] WARN conversation-list openChat fallback '
      'target=$targetConversation listed=${ids.contains(targetConversation)} '
      'count=${ids.length} homeShellTab=${st['homeShellTab']} '
      'currentConversation=${st['currentConversation']}',
    );
  }
  await ensureContactsShell(inst);
  final fullKey = 'contact_list_item:$fullId';
  final shortKey = 'contact_list_item:$friendPubkey';
  final tapped =
      await inst.tryTapKey(fullKey, retries: 2) ||
      await inst.tryTapKey(shortKey, retries: 2);
  if (!tapped) {
    throw DriveError(
      '[${inst.name}] contact tile not found for ${_shortId(friendPubkey)} '
      '(full=${_shortId(fullId)})',
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
  if (await ready()) {
    return;
  }
  final onProfile =
      await inst.waitKey('friend_profile_send_message_tile', timeoutSecs: 4) ||
      await inst.waitKey('friend_profile_send_message_button', timeoutSecs: 4);
  if (!onProfile) {
    throw DriveError(
      '[${inst.name}] contact tap for ${_shortId(friendPubkey)} did not reach '
      'either chat or friend profile',
    );
  }
  if (!await inst.tryTapKey('friend_profile_send_message_tile', retries: 2)) {
    if (!await _tryTapText(inst, 'Send Message')) {
      // Left-most tile in the [Send Message, Voice, Video] row.
      await inst.tapAt(448, 428);
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }
  }
  if (!await ready()) {
    final st = await inst.dumpState();
    throw DriveError(
      '[${inst.name}] friend profile Send Message tile did not open chat '
      'for ${_shortId(friendPubkey)} '
      '(currentConversation=${await _currentConversationId(inst)} '
      'homeShellTab=${await _homeShellTab(inst)} '
      'activeChatPeerOnline=${st['activeChatPeerOnline']})',
    );
  }
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

Future<bool> _conversationListed(Inst inst, String conversationId) async {
  final s = await inst.dumpState();
  final ids = (s['conversationIds'] as List?) ?? const [];
  return ids.contains(conversationId);
}

Future<bool> _waitConversationListed(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 6,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    if (await _conversationListed(inst, conversationId)) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

Future<void> _reopenChatFromConversationList(
  Inst inst,
  String conversationId,
) async {
  if (!await _conversationListed(inst, conversationId)) {
    return;
  }
  try {
    await inst.clearActiveConversation();
    await Future<void>.delayed(const Duration(milliseconds: 500));
  } on DriveError catch (e) {
    if (!_isNonTestAccountError(e)) rethrow;
    print(
      '[${inst.name}] WARN clearActiveConversation unavailable during '
      'conversation retap; continuing without reset',
    );
  }
  if (await _homeShellTab(inst) != 'chats') {
    await returnToChatsHome(inst, rounds: 4);
  }
  await inst.tapKey('conversation_list_item:$conversationId');
  await Future<void>.delayed(const Duration(milliseconds: 1200));
}

Future<bool> _chatSurfaceReady(
  Inst inst,
  String conversationId, {
  int timeoutSecs = 10,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (DateTime.now().isBefore(deadline)) {
    final shellTab = await _homeShellTab(inst);
    final currentConversation = await _currentConversationId(inst);
    final hasInput = await inst.waitKey(
      'chat_input_text_field',
      timeoutSecs: 1,
    );
    if (shellTab == 'chats' &&
        currentConversation == conversationId &&
        hasInput) {
      return true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
  return false;
}

/// Type [text] into the REAL composer and send it with a REAL Return, retrying
/// the focus+Return until the conversation's last message actually becomes
/// [text] (the legacy RawKeyEvent send races a freshly-typed field, so a single
/// Return is unreliable — verify-and-retry).
Future<bool> sendComposerMessage(Inst inst, String text) async {
  for (var outer = 0; outer < 2; outer++) {
    await inst.foreground();
    // The outer `chat_input_text_field` key is a reliable presence anchor, but
    // the actual editable still focuses most reliably from a direct coordinate
    // tap inside the desktop composer.
    await inst.waitKey('chat_input_text_field', timeoutSecs: 8);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    await inst.tapAt(_composerX, _composerY);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await inst.osaClear();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await inst.osaType(text);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    for (var attempt = 0; attempt < 6; attempt++) {
      await inst.foreground();
      await inst.tapAt(_composerX, _composerY); // ensure keyboard focus
      await Future<void>.delayed(const Duration(milliseconds: 450));
      await inst.osaReturn();
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      if (await _lastMessage(inst) == text) return true;
    }
    // Re-prime the chat surface once before giving up.
    await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'sendComposerMessage retry',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 2),
    );
  }
  return false;
}

Future<String?> _homeShellTab(Inst inst) async {
  final s = await inst.dumpState();
  return s['homeShellTab']?.toString();
}

Future<int> runProbeHomeRoot(Inst a, Inst b, String nickA, String nickB) async {
  await ensureHome(a, nickA);
  await ensureHome(b, nickB);
  final toxA = (await a.dumpState())['currentAccountToxId']?.toString() ?? '';
  final toxB = (await b.dumpState())['currentAccountToxId']?.toString() ?? '';
  if (toxA.isEmpty || toxB.isEmpty) {
    throw DriveError('missing tox ids for probe_home_root: A=$toxA B=$toxB');
  }
  if (!await areFriends(a, toxB) || !await areFriends(b, toxA)) {
    throw DriveError('probe_home_root requires an existing friendship');
  }
  final pairs = [(a, _pubkey(toxB)), (b, _pubkey(toxA))];
  for (final pair in pairs) {
    final inst = pair.$1;
    final peerPubkey = pair.$2;
    await openChat(inst, peerPubkey);
    final contactsOk = await _forceHomeRootAndWait(
      inst,
      tab: 'contacts',
      label: 'probe_home_root from active chat',
      ready: () => _contactsHomeReady(inst, timeoutSecs: 3),
    );
    if (!contactsOk) {
      throw DriveError(
        '[${inst.name}] probe_home_root failed to reach contacts root',
      );
    }
    final chatsOk = await _forceHomeRootAndWait(
      inst,
      tab: 'chats',
      label: 'probe_home_root from contacts root',
      ready: () => _chatsHomeReady(inst, timeoutSecs: 3),
    );
    if (!chatsOk) {
      throw DriveError(
        '[${inst.name}] probe_home_root failed to reach chats root',
      );
    }
  }
  await a.shot('/tmp/ui_probe_home_root_A.png');
  await b.foreground();
  await b.shot('/tmp/ui_probe_home_root_B.png');
  print(
    '[pair] PASS: l3_force_home_root restored contacts/chats on both peers',
  );
  return 0;
}
