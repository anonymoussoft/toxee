import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/models/tencent_cloud_chat_models.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_info.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _buildHarness({
  required V2TimFriendApplication application,
  ContactApplicationResult? applicationResult,
}) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: TencentCloudChatContactApplicationInfoButton(
        application: application,
        applicationResult:
            applicationResult ??
            ContactApplicationResult(result: '', userID: ''),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'friend application detail actions expose stable accept and decline keys',
    (tester) async {
      const userId = 'friend_detail_123';

      await tester.pumpWidget(
        _buildHarness(
          application: V2TimFriendApplication(
            userID: userId,
            nickname: 'Friend Detail',
            addWording: 'Please add me',
            faceUrl: '',
            type: 0,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(UiKeys.contactApplicationDetailAcceptButton(userId)),
        findsOneWidget,
      );
      expect(
        find.byKey(UiKeys.contactApplicationDetailDeclineButton(userId)),
        findsOneWidget,
      );
    },
  );
}
