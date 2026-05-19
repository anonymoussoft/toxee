import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sliceBetween(String src, String start, String end) {
  final s = src.indexOf(start);
  if (s < 0) {
    throw StateError(
      'control_signal_regression_test: start anchor not found: "$start"',
    );
  }
  final e = src.indexOf(end, s);
  if (e < 0) {
    throw StateError(
      'control_signal_regression_test: end anchor not found after "$start": "$end"',
    );
  }
  return src.substring(s, e);
}

void main() {
  final repoRoot = Directory.current.path;
  final routingPath =
      '$repoRoot/lib/sdk_fake/fake_msg_provider_routing.dart';
  final mappingPath =
      '$repoRoot/lib/sdk_fake/fake_msg_provider_mapping.dart';

  group('sdk_fake control-signal regressions', () {
    late String routingSrc;
    late String mappingSrc;

    setUpAll(() async {
      routingSrc = await File(routingPath).readAsString();
      mappingSrc = await File(mappingPath).readAsString();
    });

    test('live __revoke__ handling updates existing buffer instead of only swallowing', () {
      final onTopicBody = _sliceBetween(
        routingSrc,
        'Future<void> _onTopicMessage(FakeMessage m) async {',
        '/// Map FakeMessage to V2TimMessage',
      );

      expect(
        onTopicBody,
        contains('_applyRevokeControlSignalToBuffer'),
        reason:
            'Regression: sdk_fake live revoke handling still only swallows '
            'the __revoke__ control signal. It must also remove the revoked '
            'message from the current in-memory buffer so the open '
            'conversation updates immediately.',
      );
    });

    test('history reload normalizes control signals before mapping bubbles', () {
      final loadHistoryBody = _sliceBetween(
        mappingSrc,
        'Future<void> _loadHistoryForConversation(String conversationID) async {',
        '} catch (e) {',
      );

      expect(
        loadHistoryBody,
        contains('_normalizeControlSignalsInHistory'),
        reason:
            'Regression: sdk_fake history reload still feeds raw control '
            'signals directly into _mapMsg. Page reload / app restart must '
            'normalize __face__/__custom__/__location__ placeholders and '
            'apply __revoke__ removals before rebuilding the buffer.',
      );
    });

    test('history normalization helper covers revoke and placeholder rewrites', () {
      final helperBody = _sliceBetween(
        mappingSrc,
        'List<FakeMessage> _normalizeControlSignalsInHistory(',
        'Future<void> _loadHistoryForConversation(',
      );

      expect(helperBody, contains('__revoke__:'));
      expect(
        helperBody.contains('_rewriteControlSignalForBubble(msg)') ||
            (helperBody.contains('[Sticker]') &&
                helperBody.contains('[Custom Message]') &&
                helperBody.contains('[Location]')),
        isTrue,
        reason:
            'History normalization must rewrite __face__/__custom__/'
            '__location__ payloads into user-facing placeholders, either '
            'inline or via the shared rewrite helper.',
      );
    });
  });
}
