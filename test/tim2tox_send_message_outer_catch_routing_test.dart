import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String _sliceAfter(String src, String start, {String? end}) {
  final s = src.indexOf(start);
  if (s < 0) {
    throw StateError(
      'tim2tox_send_message_outer_catch_routing_test: start anchor not found: "$start"',
    );
  }
  if (end == null) return src.substring(s);
  final e = src.indexOf(end, s);
  if (e < 0) {
    throw StateError(
      'tim2tox_send_message_outer_catch_routing_test: end anchor not found after "$start": "$end"',
    );
  }
  return src.substring(s, e);
}

void main() {
  final repoRoot = Directory.current.path;
  final platformSrcPath =
      '$repoRoot/third_party/tim2tox/dart/lib/sdk/tim2tox_sdk_platform.dart';

  group('Tim2ToxSdkPlatform.sendMessage outer-catch routing', () {
    late String outerCatchBody;

    setUpAll(() async {
      final src = await File(platformSrcPath).readAsString();
      outerCatchBody = _sliceAfter(
        src,
        'sendMessage outer exception',
        end: '@override\n  Future<V2TimValueCallback<V2TimMessageListResult>> getHistoryMessageListV2({',
      );
    });

    test('recovered failed message is stamped with the target C2C route', () {
      expect(
        outerCatchBody,
        contains('failedMsg.userID = receiver.isNotEmpty ? receiver : null;'),
        reason:
            'Regression: outer-catch failure recovery still returns a '
            'message without userID. UIKit routes message updates by '
            'groupID ?? userID, so forward/send failures outside the current '
            'conversation cannot land in the target C2C thread.',
      );
    });

    test('recovered failed message is stamped with the target group route', () {
      expect(
        outerCatchBody,
        contains("failedMsg.groupID = groupID.isNotEmpty ? groupID : null;"),
        reason:
            'Regression: outer-catch failure recovery still returns a '
            'message without groupID. Forward/send failures to groups need '
            'the target group route so messageNeedUpdate and persistence are '
            'applied to the correct thread.',
      );
    });
  });
}
