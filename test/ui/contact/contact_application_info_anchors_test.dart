import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_info.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_friend_application.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _harness() {
  final application = V2TimFriendApplication(
    userID: 'friend_123',
    nickname: 'Friend 123',
    type: 0,
  );
  final result = ContactApplicationResult(result: '', userID: '');

  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: TencentCloudChatContactApplicationInfoButton(
        application: application,
        applicationResult: result,
      ),
    ),
  );
}

void main() {
  testWidgets('application detail exposes accept/decline anchor keys', (
    tester,
  ) async {
    await tester.pumpWidget(_harness());
    await tester.pump();

    expect(
      find.byKey(UiKeys.contactApplicationDetailAcceptButton('friend_123')),
      findsOneWidget,
    );
    expect(
      find.byKey(UiKeys.contactApplicationDetailDeclineButton('friend_123')),
      findsOneWidget,
    );
  });
}
