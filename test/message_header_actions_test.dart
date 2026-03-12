import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header_actions.dart';

void main() {
  testWidgets(
      'disables both call buttons when direct call actions are unavailable',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: TencentCloudChatMessageHeaderActions(
            startVoiceCall: _noop,
            startVideoCall: _noop,
            useCallKit: true,
            callActionsEnabled: false,
          ),
        ),
      ),
    );

    final buttons =
        tester.widgetList<IconButton>(find.byType(IconButton)).toList();

    expect(buttons, hasLength(2));
    expect(buttons[0].onPressed, isNull);
    expect(buttons[1].onPressed, isNull);
  });
}

void _noop() {}
