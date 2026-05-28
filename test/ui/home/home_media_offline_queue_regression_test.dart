import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('custom image/video send delegates offline queue handling to service',
      () async {
    final src = await File('lib/ui/home_page.dart').readAsString();
    final start = src.indexOf('  Future<void> _sendMedia');
    final end = src.indexOf('  Future<String> _createSelfQrCardImage', start);
    expect(start, isNonNegative);
    expect(end, greaterThan(start));

    final sendMediaBody = src.substring(start, end);

    expect(
      sendMediaBody,
      isNot(contains('widget.service.getFriendList()')),
      reason: 'FfiChatService.sendFile owns offline file queueing. The custom '
          'photo/video picker must not pre-emptively fail offline C2C sends.',
    );
    expect(
      sendMediaBody,
      contains('await widget.service.sendFile(userId, pickedPath);'),
    );
  });
}
