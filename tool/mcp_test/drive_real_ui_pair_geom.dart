// ignore_for_file: avoid_print
part of 'drive_real_ui_pair.dart';

// Shared GEOMETRY seams for the real-UI drivers.
//
// Split out of drive_real_ui_pair_chat.dart (which sits at its
// tool/.complexity_baseline.txt pin) so more than one case family can use them.
// Same library — this is organizational only.

/// Whether the RegisterPage is the route the user is actually LOOKING at.
///
/// `waitKey` (flutter_skill's element index) answers "is this key anywhere in
/// the tree", which is NOT the same question: `Navigator.push` leaves the route
/// underneath laid out, so a RegisterPage that was pushed and then covered by
/// (or returned from into) the home shell still matches. `_openRegisterPage`
/// used that check and therefore returned true while the app sat on HomePage —
/// live on iPad 2026-08-16, where `register_confirm_visibility_toggle_flips`
/// read `startObscured=true` off the covered route and then dispatched three
/// taps into the home shell, which of course changed nothing (screenshot
/// `ui_kg_confirm_vis_A.png` shows the Chats page). `ui_key_center`'s onstage
/// walk prunes exactly that case.
Future<bool> _registerPageOnstage(Inst inst, int timeoutSecs) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  while (true) {
    try {
      final r = await inst.l3('ui_key_center', {
        'key': 'register_page_nickname_field',
      });
      if (r['ok'] == true && r['onstage'] == true) return true;
    } on DriveError {
      // Fall through to the retry/timeout below.
    }
    if (!DateTime.now().isBefore(deadline)) return false;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }
}

/// `ui_key_center` with the box EXTENT that the plain `Inst.keyCenter` drops.
///
/// `keyCenter` returns only (x,y). A caller that has to aim at a FRACTION of a
/// widget needs its width too: `_openMessageMenuReal` targets the right/left
/// portion of a full-pane message row to land on an alignment-offset bubble,
/// and the old approximation ("the centre's absolute x is the pane half-width")
/// is only true when the chat pane is flush left — it put the tap OFF-SCREEN on
/// the iPad master-detail shell, where the pane starts after the sidebar and
/// the conversation list.
///
/// The `w`/`h` fields come from `uiKeyCenterHandler`
/// (lib/ui/testing/ui_drive_tools.dart). An older app build that does not
/// report them degrades to `w == 0`, and callers fall back to their keyed
/// whole-widget trigger instead of aiming at a bogus coordinate.
Future<({double x, double y, double w, double h})?> _keyBox(
  Inst inst,
  String key,
) async {
  try {
    final r = await inst.l3('ui_key_center', {'key': key});
    if (r['ok'] != true) return null;
    final x = (r['x'] as num?)?.toDouble();
    final y = (r['y'] as num?)?.toDouble();
    if (x == null || y == null) return null;
    return (
      x: x,
      y: y,
      w: (r['w'] as num?)?.toDouble() ?? 0,
      h: (r['h'] as num?)?.toDouble() ?? 0,
    );
  } on DriveError {
    return null;
  }
}

/// Wheel-scroll the open chat's list until [key]'s box sits fully ABOVE the
/// composer, i.e. inside the visible viewport. `ui_key_center` resolves an
/// onstage box even when it hangs below the fold: on Windows' shorter default
/// window (≈625 logical px) a freshly received image bubble was clipped that
/// way and the keyed tap landed on the composer instead of the bubble
/// (image_preview_open_hardened, 2026-09-04). [settleMs] first lets an async
/// image decode finish so the box measured is the final one.
Future<void> _ensureKeyInViewport(
  Inst inst,
  String key, {
  int settleMs = 1200,
}) async {
  await Future<void>.delayed(Duration(milliseconds: settleMs));
  final composer = await _keyBox(inst, 'chat_input_text_field');
  if (composer == null) return;
  final listBottom = composer.y - composer.h / 2;
  for (var step = 0; step < 6; step++) {
    final box = await _keyBox(inst, key);
    if (box == null) return;
    final overflow = box.y + box.h / 2 - listBottom;
    if (overflow <= 0) return;
    try {
      // Positive dy = wheel down (toward the newest rows); scroll over the
      // list viewport, well above the composer.
      await inst.scrollAtCoords(
        composer.x,
        (listBottom - 200).clamp(80.0, listBottom),
        dy: overflow + 24,
      );
    } on DriveError catch (e) {
      print('[${inst.name}] WARN _ensureKeyInViewport: ${e.message}');
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 350));
  }
}

/// `_keyBox` that only returns once two CONSECUTIVE reads agree to within half
/// a logical pixel in position AND extent, or null when [key] never settled
/// (or stayed absent / unsized) before [timeoutSecs]. Same remedy as
/// `Inst.tapKeyCenter(stableBounds:)` and `waitKeyCenterSettled`: a box read
/// during a list remount or a slide-in is a box the pointer will miss.
Future<({double x, double y, double w, double h})?> _stableKeyBox(
  Inst inst,
  String key, {
  int timeoutSecs = 4,
}) async {
  final deadline = DateTime.now().add(Duration(seconds: timeoutSecs));
  ({double x, double y, double w, double h})? prev;
  while (DateTime.now().isBefore(deadline)) {
    final cur = await _keyBox(inst, key);
    if (cur != null &&
        cur.w > 0 &&
        prev != null &&
        (cur.x - prev.x).abs() < 0.5 &&
        (cur.y - prev.y).abs() < 0.5 &&
        (cur.w - prev.w).abs() < 0.5 &&
        (cur.h - prev.h).abs() < 0.5) {
      return cur;
    }
    prev = cur;
    await Future<void>.delayed(const Duration(milliseconds: 150));
  }
  return null;
}

/// Open the REAL message context menu for [msgId] with the shell's own trigger
/// — a genuine secondary-tap (desktop `_openDesktopMessageMenu`) or a genuine
/// long-press (mobile `_onLongPressMessageOnMobile`). No gated tool either way.
/// Returns whether at least one keyed `message_menu_item:*` rendered.
/// Foregrounds first + retries.
///
/// WHY THE BRANCH: a mobile shell has no secondary-button pointer, so
/// `ui_secondary_tap` dispatches a kSecondaryMouseButton PointerDown the
/// bubble's Listener never treats as a menu open — every menu-driven chat case
/// hard-failed on iOS/Android. The mobile twin is a real touch down→hold→up at
/// 800 ms (past the 500 ms framework deadline AND the fork's 650 ms
/// recognizer), the trigger `mobile_message_long_press_menu` already proves out
/// in drive_real_ui_pair_mobile_shell.dart. Desktop behaviour is unchanged.
///
/// WHERE THE POINTER GOES (root-caused 2026-09-05, iPhone sweep_msg_select).
/// The long-press recognizer sits on the BUBBLE (the `GestureDetector` around
/// `getMessageItemWidget` in tencent_cloud_chat_message_item_with_menu.dart),
/// which is alignment-offset inside a full-width row whose remaining width is
/// a transparent Container that receives nothing. The old ladder aimed at
/// FRACTIONS of the row width [0.72, 0.15, 0.85, 0.5, 0.28]. On a 402 pt phone
/// row an INBOUND bubble spans ≈62..185 pt (avatar column 10+36+10 = 56 pt,
/// tencent_cloud_chat_message_row.dart), so 0.72 / 0.85 / 0.5 were empty
/// space, 0.15 (60 pt) was the gap between the avatar and the bubble, and only
/// the LAST attempt (0.28 = 113 pt, ~27 s in) touched the bubble at all. One
/// attempt is exactly what a transient steals: on a FRESH chat the first
/// message creates the conversation, and the list container then re-keys the
/// whole MessageList (`_messageListKey = UniqueKey()` in
/// tencent_cloud_chat_message_list_view_container.dart, `_dataProviderListener`)
/// — every row unmounts and remounts, killing an in-flight recognizer. Live:
/// `ui_long_press … key_not_found` mid-ladder on the run that then passed on
/// the 0.28 attempt; the run that failed had its single bubble hit inside that
/// window. The box was also read ONCE before the ladder, so any shift left
/// every retry aiming at a stale y.
///
/// Now, per attempt: the row box is re-resolved and required STABLE (two
/// consecutive identical reads — what `tapKeyCenter(stableBounds:)` does for
/// mid-animation targets), and on the mobile shell the press is aimed at PIXEL
/// offsets inside the bubble measured from the row's OWN edge — past the 56 pt
/// avatar column (both sides: toxee shows the self avatar too,
/// lib/ui/home_page_bootstrap.dart `showSelfAvatar`) by 30 / 60 pt — so the
/// inbound and the self bubble are each hit on the first or second attempt
/// regardless of pane width. [isSelf] orders the side to try first (null =
/// self first, the historical order for the own-message callers). The desktop
/// fraction ladder (live-probed) is unchanged apart from the fresh, stable box.
Future<bool> _openMessageMenuReal(
  Inst inst,
  String msgId, {
  bool? isSelf,
}) async {
  await inst.foreground();
  // Pop the friend's contact profile if it covers the chat — the row is then
  // offstage behind it and the trigger hits the profile ("menu did not open").
  await _dismissFriendProfileToUnderlying(inst);
  final rowKey = 'message_list_item:$msgId';
  if (!await inst.waitKey(rowKey, timeoutSecs: 8)) {
    // WHERE is the app? "row not present" cannot tell a missing bubble from a
    // chat surface that left the stack (narrow shell: a dismiss tap that popped
    // the pushed route) — the ambiguity that cost a shift on kg3's receipt case.
    print(
      '[pair] _openMessageMenuReal: row $rowKey not present — '
      '${await _convShellDiag(inst)}',
    );
    return false;
  }
  // Desktop: row-RELATIVE fractions (the iPad master-detail pane starts after
  // the sidebar + conversation list, so scaling an absolute x put the taps
  // off-screen / in the list). 0.72/0.85 sit on a right-aligned self bubble
  // (0.72 reproduces the live-probed hit at x≈1030 of a 382..1280 pane),
  // 0.15/0.28 on a left-aligned peer bubble, 0.5 is the keyed row centre.
  const desktopFractions = <double>[0.72, 0.15, 0.85, 0.28, 0.6, 0.4, 0.5];
  // Mobile: pt offsets from the bubble-side row edge. Positive = from the
  // LEFT edge (inbound), negative = from the RIGHT edge (self); 0 = the keyed
  // row centre, kept last as the wide-bubble catch-all.
  const selfOffsets = <double>[-86, -116];
  const peerOffsets = <double>[86, 116];
  final mobileOffsets = <double>[
    for (var i = 0; i < 2; i++) ...[
      if (isSelf != false) selfOffsets[i],
      if (isSelf != true) peerOffsets[i],
    ],
    0,
  ];
  final plan = inst.isMobileShell ? mobileOffsets : desktopFractions;
  ({double x, double y, double w, double h})? rowBox;
  var lastAim = '';
  for (var attempt = 0; attempt < plan.length; attempt++) {
    // FRESH + STABLE per attempt: a remounted or shifted row must never be
    // pressed at the coordinates of its previous incarnation.
    rowBox = await _stableKeyBox(inst, rowKey);
    final p = plan[attempt];
    double? x;
    if (rowBox != null && rowBox.w > 0) {
      if (!inst.isMobileShell) {
        if (p != 0.5) x = rowBox.x - rowBox.w / 2 + p * rowBox.w;
      } else if (p > 0) {
        x = rowBox.x - rowBox.w / 2 + p;
      } else if (p < 0) {
        x = rowBox.x + rowBox.w / 2 + p;
      }
    }
    lastAim = x == null ? 'keyed' : '($x, ${rowBox!.y})';
    var tapped = false;
    try {
      if (inst.isMobileShell) {
        if (x != null) {
          final r = await inst.l3('ui_long_press', {
            'x': '$x',
            'y': '${rowBox!.y}',
            'holdMs': '800',
          });
          if (r['ok'] != true) {
            print('[pair] _openMessageMenuReal: ui_long_press warn: $r');
          }
        } else {
          await inst.longPressKey(rowKey);
        }
      } else if (x != null) {
        await inst.secondaryTapAt(x, rowBox!.y);
      } else {
        await inst.secondaryTapKey(rowKey);
      }
      tapped = true;
    } on DriveError catch (e) {
      print('[pair] _openMessageMenuReal: menu trigger warn: ${e.message}');
    }
    if (!tapped) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      continue;
    }
    // The mobile menu animates in after the hold releases — give it the same
    // 900 ms `mobile_message_long_press_menu` settled on.
    await Future<void>.delayed(
      Duration(milliseconds: inst.isMobileShell ? 900 : 700),
    );
    // The desktop context menu renders in an `Overlay.insert` entry that
    // flutter_skill's waitForElement/interactiveStructured does NOT traverse
    // (it only ever matched the now-keyless OFFSTAGE measurement copy). Detect
    // it via the ELEMENT-TREE resolver (`waitKeyCenter` → resolveKeyCenter),
    // which walks the full tree including overlays. Taps still go through
    // tapKeyCenter, which falls back to the same resolver.
    if (await inst.waitKeyCenter('message_menu_item:copy', timeoutSecs: 3) ||
        await inst.waitKeyCenter('message_menu_item:delete', timeoutSecs: 2)) {
      return true;
    }
  }
  await inst.shot('/tmp/ui_open_msg_menu_fail_${inst.name}.png');
  print(
    '[pair] _openMessageMenuReal: menu did not open for $rowKey '
    '(isSelf=$isSelf plan=$plan lastAim=$lastAim lastRowBox=$rowBox) '
    'shot=/tmp/ui_open_msg_menu_fail_${inst.name}.png',
  );
  return false;
}

/// Plain tap on the INBOUND bubble of message row [rowKey] (the file / image
/// bubbles' `onTap` opener), aimed like [_openMessageMenuReal]'s peer offsets:
/// [offset] pt in from the row's LEFT edge, on a STABLE row box. The row's
/// centre is empty space beside a left-aligned bubble on any pane wider than
/// the bubble (live: the iPad master-detail pane never opened the file
/// preview because `tapKeyCenter` hit the row centre), so callers that need
/// the bubble's handler must aim at the bubble. Returns false (no tap) when
/// the row never settled; callers fall back to the keyed centre.
Future<bool> _tapInboundBubble(
  Inst inst,
  String rowKey, {
  double offset = 116,
}) async {
  final box = await _stableKeyBox(inst, rowKey);
  if (box == null || box.w <= offset) {
    print('[${inst.name}] tapInboundBubble: no stable row box for $rowKey');
    return false;
  }
  final x = box.x - box.w / 2 + offset;
  print('[${inst.name}] tapInboundBubble: aim=($x, ${box.y}) row=$box');
  await inst.shot('/tmp/ui_tap_inbound_pretap_${inst.name}.png');
  await inst.tapAt(x, box.y);
  return true;
}

/// The image bubble's tap pushes the full-screen message viewer
/// (`message_viewer_root`, whose own onTap is `closeViewer`). A case that
/// opens it MUST close it: on the wide shell nothing downstream pops it — the
/// pane's landmarks still resolve UNDER it, so `returnToChatsHome` reports
/// ready — and the next case's taps land on black (live: the iPad file case
/// failed three runs in a row this way). Returns whether the viewer was open
/// and whether it is closed now (true when it never opened).
Future<({bool opened, bool closed})> _closeImagePreviewIfOpen(Inst inst) async {
  if (!await inst.waitKey('message_viewer_root', timeoutSecs: 4)) {
    return (opened: false, closed: true);
  }
  var closed = false;
  for (var i = 0; i < 3 && !closed; i++) {
    if (!await inst.tapKeyCenter('message_viewer_root', timeoutSecs: 2)) {
      await inst.skill('goBack');
    }
    closed = await inst.waitKeyGone('message_viewer_root', timeoutSecs: 4);
  }
  print('[${inst.name}] image preview: opened=true closed=$closed');
  return (opened: true, closed: closed);
}
