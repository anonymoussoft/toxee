import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_contact_group_application_list.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_application.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _buildHarness(String groupId) {
  final application = V2TimGroupApplication(
    groupID: groupId,
    fromUser: 'friend_123',
    toUser: 'self_123',
    type: 0,
    handleStatus: 0,
    handleResult: 0,
  );

  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates:
        TencentCloudChatLocalizations.localizationsDelegates,
    supportedLocales: TencentCloudChatLocalizations.supportedLocales,
    home: Scaffold(
      body: TencentCloudChatContactGroupApplicationItemButton(
        application: application,
      ),
    ),
  );
}

void main() {
  testWidgets('group invite accept action exposes a stable anchor key', (
    tester,
  ) async {
    const groupId = 'group_123';

    await tester.pumpWidget(_buildHarness(groupId));
    await tester.pump();

    expect(find.byKey(UiKeys.groupInviteAcceptButton(groupId)), findsOneWidget);
  });
}
