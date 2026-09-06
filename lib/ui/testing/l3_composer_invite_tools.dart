// L3 composer / invite tools — `l3_composer_send` and `l3_invite_to_group`.
//
// Both moved out of `l3_debug_tools.dart` (pinned in
// `tool/.complexity_baseline.txt`) in the same change, because both had the
// same defect class: a result the real-UI driver TRUSTED that did not say
// whether the thing actually happened.
//
//   * `l3_invite_to_group` answered `ok:true` on the SDK call's `code == 0`,
//     but the C++ `InviteUserToGroup` maps a failed `tox_group_invite_friend`
//     (friend link not online yet, group not found, ...) to a PER-MEMBER
//     `V2TIM_GROUP_MEMBER_RESULT_FAIL` and still calls OnSuccess — so a lost
//     invite surfaced only as "B did not auto-join" 45 s later. The tool now
//     inspects every member result (`debugL3InviteResultContract`).
//   * `l3_composer_send` answered `ok:true` when ANY composer seam was mounted.
//     The seams are process-global and on a phone `_openChat` binds the
//     conversation BEFORE it pushes the message route, so a send issued as soon
//     as the conversation id read right went to the PREVIOUS chat's composer.
//     The tool now reports the mounted composer's binding
//     (`seam` / `boundUserID` / `boundGroupID`, from the fork's
//     `debugRealUi*ComposerBinding` seams) and offers `probe:true` so a driver
//     can wait for the right composer before sending.
//
// A `part` rather than its own library on purpose: `_activeAccountIsTest` and
// the fork seam imports live in `l3_debug_tools.dart`.

part of 'l3_debug_tools.dart';

void _registerL3ComposerInviteTools() {
  addMcpTool(_l3ComposerSendEntry());
  addMcpTool(_l3InviteToGroupEntry());
}

/// `V2TIM_GROUP_MEMBER_RESULT_SUCC` (third_party/tim2tox/include/V2TIMGroup.h);
/// the SDK model's `_OPERATION_RESULT_SUCC`. Anything else — FAIL (0), INVALID
/// (2, already a member), PENDING (3) — is not a delivered invite.
const int _kGroupMemberResultSucc = 1;

/// The `l3_invite_to_group` result contract, pure so a unit test can pin it:
/// `ok` only when the SDK call succeeded AND every per-member result is SUCC.
/// `members` carries each `{userId, result}` so a failure is diagnosable from
/// the driver log, and `error` names the failing layer.
Map<String, Object?> debugL3InviteResultContract(
  V2TimValueCallback<List<V2TimGroupMemberOperationResult>> res, {
  required String groupId,
  required String userId,
}) {
  final members = <Map<String, Object?>>[
    for (final r in res.data ?? const <V2TimGroupMemberOperationResult>[])
      {'userId': r.memberID, 'result': r.result},
  ];
  String? error;
  if (res.code != 0) {
    error = 'invite_failed';
  } else if (members.isEmpty) {
    error = 'no_member_result';
  } else if (members.any((m) => m['result'] != _kGroupMemberResultSucc)) {
    error = 'member_invite_failed';
  }
  return {
    'ok': error == null,
    'code': res.code,
    'desc': res.desc,
    'groupId': groupId,
    'userId': userId,
    'members': members,
    if (error != null) 'error': error,
  };
}

/// The mounted composer as `l3_composer_send` sees it: which seam family it
/// would drive (`desktop` wins over `mobile`, mirroring the send precedence
/// below; `none` when nothing is mounted) and the conversation that composer
/// is bound to. Pure over the fork's debug globals so a widget test can pin it.
Map<String, Object?> debugL3ComposerSeamSnapshot() {
  final desktop =
      debugRealUiDesktopComposerSendText != null ||
      debugRealUiDesktopComposerSend != null;
  final mobile =
      debugRealUiMobileComposerSendText != null ||
      debugRealUiMobileComposerSend != null;
  final binding = desktop
      ? debugRealUiDesktopComposerBinding?.call()
      : mobile
      ? debugRealUiMobileComposerBinding?.call()
      : null;
  return {
    'seam': desktop
        ? 'desktop'
        : mobile
        ? 'mobile'
        : 'none',
    'boundUserID': binding?.userID,
    'boundGroupID': binding?.groupID,
  };
}

MCPCallEntry _l3ComposerSendEntry() => MCPCallEntry.tool(
  handler: (request) async {
    final text = request['text']?.toString();
    final seam = debugL3ComposerSeamSnapshot();
    if (request['probe']?.toString().toLowerCase() == 'true') {
      // Read-only: report the mounted composer's binding without sending, so
      // a driver can wait for `boundGroupID == <target>` before it sends.
      return MCPCallResult(
        message: 'composer seam probe',
        parameters: {'ok': seam['seam'] != 'none', 'probe': true, ...seam},
      );
    }
    // Mixed macOS<->iOS / mobile: prefer the combined set-text-and-send seam so a
    // macOS peer can send over the VM service while a Simulator peer holds the
    // foreground (no osascript keystrokes), and the mobile composer (which
    // ignores synthetic enterText) sends via the production path.
    if (text != null) {
      final combined =
          debugRealUiDesktopComposerSendText ??
          debugRealUiMobileComposerSendText;
      if (combined != null) {
        combined(text);
        return MCPCallResult(
          message: 'composer text sent',
          parameters: {'ok': true, 'length': text.length, ...seam},
        );
      }
    }
    // Desktop / Windows: set the field DIRECTLY (flutter_skill enterText can't
    // reach this composer's controller headless on Windows), then invoke the REAL
    // Enter-send (the exact inputMethods.sendTextMessage path).
    //
    // The MOBILE composer falls back to its own send-only seam. Without it, a
    // no-`text` call on any phone/tablet shell answered `no_active_composer` and
    // silently sent nothing — which is what made both `mobile_mention_picker_*`
    // cases fail: the text they must send is written by the app's own
    // `_submitAtMemberList`, so they cannot supply it as an argument.
    final hook =
        debugRealUiDesktopComposerSend ?? debugRealUiMobileComposerSend;
    if (hook == null) {
      return MCPCallResult(
        message: 'l3_composer_send: no composer mounted',
        parameters: {'ok': false, 'error': 'no_active_composer', ...seam},
      );
    }
    if (text != null) {
      final setText = debugRealUiDesktopComposerSetText;
      if (setText != null) {
        setText(text);
        // Let the field rebuild with the new text before the send reads it.
        await Future<void>.delayed(const Duration(milliseconds: 60));
      }
    }
    hook();
    return MCPCallResult(
      message: 'composer send invoked',
      parameters: {'ok': true, ...seam},
    );
  },
  definition: MCPToolDefinition(
    name: 'l3_composer_send',
    description:
        'L3 TEST ONLY: send the open chat composer text via the production '
        'inputMethods.sendTextMessage path (the Enter-key / send-button code). '
        'With "text" set the field first (deterministic); routes to the mobile / '
        'mixed-run combined seam when mounted, else the desktop set-text+Enter '
        'path. With "probe" true, only report the mounted composer (no send). '
        'Returns {ok, seam: desktop|mobile|none, boundUserID, boundGroupID, '
        'error?} — gate a group send on boundGroupID.',
    inputSchema: ObjectSchema(
      properties: {
        'text': StringSchema(
          description: 'Optional text to set in the composer before sending.',
        ),
        'probe': StringSchema(
          description:
              'true | false: when true, report the mounted composer binding '
              'without sending.',
        ),
      },
    ),
  ),
);

/// S47/S81: invite a friend to an NGC group via the SDK group manager
/// (`getGroupManager().inviteUserToGroup` → native_im adapter →
/// `DartInviteUserToGroup` → C++ `tox_group_invite_friend`), the SAME path the
/// UIKit add-member flow uses. With the invitee's `autoAcceptGroupInvites=true`
/// (l3_set_setting), the C++ pipeline auto-joins via `tox_group_invite_accept`.
/// `ok` is the per-member contract (see [debugL3InviteResultContract]): the
/// C++ side reports a refused `tox_group_invite_friend` as a member FAIL under
/// an OnSuccess, which `code == 0` alone read as "invite sent".
/// MUTATING, test/seed account.
MCPCallEntry _l3InviteToGroupEntry() => MCPCallEntry.tool(
  handler: (request) async {
    if (!await _activeAccountIsTest()) {
      return MCPCallResult(
        message: 'l3_invite_to_group: refused — non-test account',
        parameters: {'ok': false, 'error': 'non_test_account'},
      );
    }
    var groupId = (request['groupId'] as Object?)?.toString().trim() ?? '';
    if (groupId.startsWith('group_')) groupId = groupId.substring(6);
    final userId = (request['userId'] as Object?)?.toString().trim() ?? '';
    if (groupId.isEmpty || userId.isEmpty) {
      return MCPCallResult(
        message: 'l3_invite_to_group: need "groupId" and "userId"',
        parameters: {'ok': false, 'error': 'missing_args'},
      );
    }
    try {
      final res = await TencentImSDKPlugin.v2TIMManager
          .getGroupManager()
          .inviteUserToGroup(groupID: groupId, userList: [userId]);
      final contract = debugL3InviteResultContract(
        res,
        groupId: groupId,
        userId: userId,
      );
      AppLogger.info(
        '[L3] l3_invite_to_group: group=$groupId user=$userId '
        'code=${res.code} desc=${res.desc} members=${contract['members']}',
      );
      return MCPCallResult(
        message: contract['ok'] == true
            ? 'invite sent'
            : 'invite failed (${contract['error']}, code=${res.code})',
        parameters: contract,
      );
    } catch (e, st) {
      AppLogger.logError('[L3] l3_invite_to_group failed', e, st);
      return MCPCallResult(
        message: 'l3_invite_to_group: failed: $e',
        parameters: {'ok': false, 'error': 'invite_failed', 'detail': '$e'},
      );
    }
  },
  definition: MCPToolDefinition(
    name: 'l3_invite_to_group',
    description:
        'L3 TEST ONLY (test/seed account, MUTATING): invite a friend to an NGC '
        'group via the SDK group manager (reaches C++ tox_group_invite_friend). '
        'With the invitee autoAcceptGroupInvites=true, they auto-join. ok is '
        'false when any per-member result is not SUCC (members lists them).',
    inputSchema: ObjectSchema(
      properties: {
        'groupId': StringSchema(
          description: 'Group id (local tox_N or chat-id).',
        ),
        'userId': StringSchema(description: 'Friend Tox ID to invite.'),
      },
      required: ['groupId', 'userId'],
    ),
  ),
);
