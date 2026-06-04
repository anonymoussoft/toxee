import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _harness(Widget child) {
  return MaterialApp(home: Scaffold(body: child));
}

void main() {
  testWidgets('conversation avatar exposes a stable online-dot anchor', (
    tester,
  ) async {
    final conversation = V2TimConversation(conversationID: 'c2c_friend_123');

    await tester.pumpWidget(
      _harness(
        TencentCloudChatConversationItemAvatar(
          conversation: conversation,
          isOnline: true,
        ),
      ),
    );
    await tester.pump();

    expect(
      find.byKey(UiKeys.conversationItemOnlineDot('c2c_friend_123')),
      findsOneWidget,
    );
  });
}
