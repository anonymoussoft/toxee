// Regression guard for P1-1: outbound **file-send** msgIDs in
// `FfiChatService.sendFile` must include the process-monotonic
// `_msgIDSequence` counter, not just `millisecondsSinceEpoch`.
//
// Why: two file sends fired back-to-back in the same millisecond would
// otherwise share an identical msgID like `"1700000000000_<selfId>"`, and
// the history-dedup path treats msgID as the primary identity. The second
// message would be silently dropped from the on-disk history and from the
// UIKit list. The fix (around line ~4970) bakes `_msgIDSequence++` into the
// generated string.
//
// Strategy — degraded "source-string assertion":
// Driving the real send path requires live FFI + Tox sockets, far beyond
// what a unit test should set up. We instead pin the fix textually by
// anchoring on the `P1-1:` comment the fix introduced — that's the most
// stable marker; the line number drifts as `ffi_chat_service.dart` evolves.
//
// Scoping notes:
// - The text-send path (`sendText`) was ALSO sequence-free until 2026-05-29,
//   when the same collision class was found via the L3 multi-send runner and
//   fixed (anchor comment `P1-1 (text-send):`). The second test below now
//   guards it. Both anchors use the `P1-1` tag but differ after it
//   (`P1-1:` for file-send, `P1-1 (text-send):` for text-send), so the two
//   tests pin distinct construction sites.
// - The legacy fallback in `deleteMessages` reconstructs msgIDs from
//   `msg.timestamp.millisecondsSinceEpoch` + `msg.fromUserId` *intentionally*
//   without a sequence (so it can match pre-sequence on-disk records).
//   That line uses `${msg.fromUserId}`, not `$_selfId`, so the anchor
//   below doesn't pick it up.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final repoRoot = Directory.current.path;
  final ffiChatServicePath =
      '$repoRoot/third_party/tim2tox/dart/lib/service/ffi_chat_service.dart';

  test(
    'outbound file-send msgID includes _msgIDSequence (P1-1 collision fix)',
    () async {
      final src = await File(ffiChatServicePath).readAsString();
      final lines = src.split('\n');

      // Find the P1-1 anchor comment. This is the most stable signal: the
      // comment was added together with the fix and explains *why* the
      // sequence is in the template. If a future refactor moves the
      // construction, the comment should move with it (or be replaced by
      // a different fix that we'd want to re-assert here anyway).
      //
      // Anchor on the literal `P1-1:` prefix — the colon distinguishes the
      // fix tag from any incidental mention of "P1-1" in surrounding prose.
      var anchorIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('P1-1:')) {
          anchorIdx = i;
          break;
        }
      }

      expect(
        anchorIdx,
        isNonNegative,
        reason:
            'P1-1 comment marker missing from ffi_chat_service.dart. Either '
            'the file was refactored or the P1-1 fix for outbound file-send '
            'msgID collisions was reverted. Look for the comment block '
            'starting "P1-1: include the same monotonic sequence...".',
      );

      // The actual msgID assignment must follow the comment within a few
      // lines and must contain `_msgIDSequence` interpolated next to
      // `$_selfId` — that's the format the fix uses today:
      //   '${DateTime.now().millisecondsSinceEpoch}_${_msgIDSequence++}_$_selfId'
      const lookahead = 8;
      final end = (anchorIdx + lookahead).clamp(0, lines.length);
      final window = lines.sublist(anchorIdx, end).join('\n');

      expect(
        window,
        contains('_msgIDSequence'),
        reason:
            'P1-1 regression: outbound file-send msgID construction near the '
            'P1-1 comment no longer references _msgIDSequence. Back-to-back '
            'file sends in the same millisecond will produce identical '
            'msgIDs and the second one will be deduped out of history.',
      );
      expect(
        window,
        contains(r'$_selfId'),
        reason:
            'P1-1 regression: outbound file-send msgID template no longer '
            'interpolates \$_selfId after the P1-1 comment — the fix lives '
            'in a different shape now; re-assert this test against the new '
            'construction or delete it.',
      );
      expect(
        window,
        contains('millisecondsSinceEpoch'),
        reason:
            'P1-1 regression: outbound file-send msgID template no longer '
            'uses millisecondsSinceEpoch as the wall-clock component — '
            'verify the fix is still doing what it claims to do.',
      );
    },
  );

  test(
    'outbound text-send msgID includes _msgIDSequence (P1-1 text-send fix)',
    () async {
      // Sibling of the file-send guard above. The online `sendText` path used
      // a sequence-free `${ms}_$_selfId` msgID until 2026-05-29; two C2C texts
      // in the same millisecond collided and the second was deduped out of
      // history. Anchor on the distinct `P1-1 (text-send):` comment.
      final src = await File(ffiChatServicePath).readAsString();
      final lines = src.split('\n');

      var anchorIdx = -1;
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('P1-1 (text-send):')) {
          anchorIdx = i;
          break;
        }
      }

      expect(
        anchorIdx,
        isNonNegative,
        reason:
            'P1-1 text-send comment marker missing from ffi_chat_service.dart. '
            'The online sendText msgID collision fix was reverted or moved. '
            'Look for "P1-1 (text-send): include the monotonic _msgIDSequence".',
      );

      // The construction must follow the comment within a few lines and carry
      // the same three components as the inbound/file templates.
      const lookahead = 8;
      final end = (anchorIdx + lookahead).clamp(0, lines.length);
      final window = lines.sublist(anchorIdx, end).join('\n');

      expect(
        window,
        contains('_msgIDSequence'),
        reason:
            'P1-1 text-send regression: online sendText msgID near the '
            'P1-1 (text-send) comment no longer references _msgIDSequence. '
            'Back-to-back text sends in the same millisecond will collide and '
            'the second will be deduped out of history.',
      );
      expect(
        window,
        contains(r'$_selfId'),
        reason:
            'P1-1 text-send regression: sendText msgID template no longer '
            'interpolates \$_selfId after the P1-1 (text-send) comment.',
      );
      expect(
        window,
        contains('millisecondsSinceEpoch'),
        reason:
            'P1-1 text-send regression: sendText msgID template no longer '
            'uses millisecondsSinceEpoch as the wall-clock component.',
      );
    },
  );
}
