import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile_body.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

void main() {
  testWidgets(
      'disables voice and video buttons on the profile page when the friend is offline',
      (tester) async {
    TencentCloudChat.instance.dataInstance.contact.buildUserStatusList(
      [
        V2TimUserStatus(
          userID: 'offline-user',
          statusType: 0,
          onlineDevices: const [],
        ),
      ],
      'test',
    );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates:
            TencentCloudChatLocalizations.localizationsDelegates,
        supportedLocales: TencentCloudChatLocalizations.supportedLocales,
        home: Scaffold(
          body: TencentCloudChatUserProfileChatButton(
            userFullInfo: V2TimUserFullInfo(userID: 'offline-user'),
            isNavigatedFromChat: true,
          ),
        ),
      ),
    );

    final buttons = tester.widgetList<InkWell>(find.byType(InkWell)).toList();

    expect(buttons, hasLength(3));
    expect(buttons[0].onTap, isNotNull);
    expect(buttons[1].onTap, isNull);
    expect(buttons[2].onTap, isNull);
  });
}
