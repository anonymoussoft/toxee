import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/tencent_cloud_chat_contact_builders.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_application_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _buildHarness(V2TimFriendApplication application) {
  TencentCloudChat.instance.dataInstance.contact.contactBuilder =
      TencentCloudChatContactBuilders();

  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: TencentCloudChatContactApplicationItem(application: application),
    ),
  );
}

void main() {
  testWidgets(
    'friend application row exposes stable keys for row, actions, and wording',
    (tester) async {
      const userId = 'friend_123';
      const wording = 'Please add me';

      await tester.pumpWidget(
        _buildHarness(
          V2TimFriendApplication(
            userID: userId,
            nickname: 'Friend 123',
            addWording: wording,
            type: 0,
          ),
        ),
      );
      await tester.pump();

      expect(find.byKey(UiKeys.contactApplicationItem(userId)), findsOneWidget);
      expect(
        find.byKey(UiKeys.contactApplicationAcceptButton(userId)),
        findsOneWidget,
      );
      expect(
        find.byKey(UiKeys.contactApplicationDeclineButton(userId)),
        findsOneWidget,
      );

      final wordingFinder = find.byKey(
        UiKeys.contactApplicationAddWording(userId),
      );
      expect(wordingFinder, findsOneWidget);
      expect(tester.widget<Text>(wordingFinder).data, wording);
    },
  );

  testWidgets(
    'friend application row omits the add-wording key when no wording is present',
    (tester) async {
      const userId = 'friend_without_wording';

      await tester.pumpWidget(
        _buildHarness(
          V2TimFriendApplication(
            userID: userId,
            nickname: 'No Wording',
            addWording: '',
            type: 0,
          ),
        ),
      );
      await tester.pump();

      expect(
        find.byKey(UiKeys.contactApplicationAddWording(userId)),
        findsNothing,
      );
    },
  );
}
