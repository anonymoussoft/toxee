import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/components/component_options/tencent_cloud_chat_user_profile_options.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_contact/widgets/tencent_cloud_chat_user_profile.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';

void main() {
  testWidgets('user profile app bar prefers nickname over full user ID', (
    tester,
  ) async {
    const userId =
        'FB13309421557E8D386A1BC9C022156EE85F12DB8E6FE867BBDF42C8B2A74C0B';
    const nickname = 'RealUiBob';

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates:
            TencentCloudChatLocalizations.localizationsDelegates,
        supportedLocales: TencentCloudChatLocalizations.supportedLocales,
        home: TencentCloudChatUserProfile(
          options: TencentCloudChatUserProfileOptions(
            userID: userId,
            userFullInfo: V2TimUserFullInfo(userID: userId, nickName: nickname),
          ),
        ),
      ),
    );

    await tester.pump();

    expect(find.text(nickname), findsWidgets);
    expect(find.textContaining('ID: $userId'), findsOneWidget);
  });
}
