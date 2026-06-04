import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_header/tencent_cloud_chat_message_header_actions.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

void main() {
  testWidgets('chat header call actions expose stable UiKeys', (tester) async {
    var voiceTapCount = 0;
    var videoTapCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TencentCloudChatMessageHeaderActions(
            startVoiceCall: () => voiceTapCount += 1,
            startVideoCall: () => videoTapCount += 1,
            useCallKit: true,
          ),
        ),
      ),
    );

    expect(find.byKey(UiKeys.chatCallVoiceButton), findsOneWidget);
    expect(find.byKey(UiKeys.chatCallVideoButton), findsOneWidget);

    await tester.tap(find.byKey(UiKeys.chatCallVoiceButton));
    await tester.pump();
    await tester.tap(find.byKey(UiKeys.chatCallVideoButton));
    await tester.pump();

    expect(voiceTapCount, 1);
    expect(videoTapCount, 1);
  });
}
