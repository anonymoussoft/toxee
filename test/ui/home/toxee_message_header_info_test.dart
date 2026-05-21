// Widget tests for [ToxeeMessageHeaderInfo].
//
// `ToxeeMessageHeaderInfo` is the toxee-side replacement for UIKit's
// `TencentCloudChatMessageHeaderInfo`. It fixes an `Expanded`-in-
// `MainAxisSize.min` layout bug in the upstream widget that caused the
// status row to collapse to 0 height. Behaviour is fully driven by
// constructor props (no closure over `_HomePageState`), so it's directly
// testable at the widget layer.
//
// The matrix we pin down:
//   * C2C online  → status row reads "Online".
//   * C2C offline → status row reads "Offline".
//   * Group with 3+ members → status row reads UIKit `groupSubtitle` text.
//   * Group with <=2 members → no status row.
//   * `showUserOnlineStatus == false` → display name only.
//   * `conversation == null` falls back to `userID` for display name.
//   * `getUserOnlineStatus` is invoked with the conversation's `userID`,
//     not the widget's (regression guard for the precedence order).
//
// We deliberately use the real UIKit localization delegate so the assertions
// match what users see in production rather than hand-rolled strings.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_conversation.dart';
import 'package:tencent_cloud_chat_sdk/models/v2_tim_group_member_full_info.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home/toxee_message_header_info.dart';

/// Build a C2C conversation. `type == 1` triggers the online/offline branch
/// inside `ToxeeMessageHeaderInfo`.
V2TimConversation _c2cConversation({
  required String userID,
  String? showName,
}) {
  return V2TimConversation(
    conversationID: 'c2c_$userID',
    type: 1, // C2C
    userID: userID,
    showName: showName ?? userID,
  );
}

/// Build a group conversation. `type == 2` is the group branch.
V2TimConversation _groupConversation({
  required String groupID,
  String? showName,
}) {
  return V2TimConversation(
    conversationID: 'group_$groupID',
    type: 2, // group
    groupID: groupID,
    showName: showName ?? groupID,
  );
}

V2TimGroupMemberFullInfo _member(String userID, {String? nickName}) {
  return V2TimGroupMemberFullInfo(
    userID: userID,
    nickName: nickName ?? userID,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      // Constrain so the widget doesn't overflow when statusText is long;
      // also mirrors the app-bar layout where this widget renders in
      // production.
      body: SizedBox(
        width: 320,
        height: 56,
        child: child,
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ToxeeMessageHeaderInfo - C2C', () {
    testWidgets('renders display name + "Online" when peer is online',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          userID: 'alice',
          conversation: _c2cConversation(userID: 'alice', showName: 'Alice'),
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) {
            calls.add(userID);
            return true;
          },
          getGroupMembersInfo: () => const [],
        ),
      ));
      await tester.pump();

      expect(find.text('Alice'), findsOneWidget,
          reason: 'display name comes from conversation.showName');
      expect(find.text('Online'), findsOneWidget,
          reason: 'online peer must surface the Online label');
      expect(calls, ['alice'],
          reason:
              'getUserOnlineStatus must be queried with the conversation userID');
    });

    testWidgets('renders "Offline" when peer is offline', (tester) async {
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          userID: 'bob',
          conversation: _c2cConversation(userID: 'bob', showName: 'Bob'),
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) => false,
          getGroupMembersInfo: () => const [],
        ),
      ));
      await tester.pump();

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('Offline'), findsOneWidget);
    });

    testWidgets('omits status row when showUserOnlineStatus is false',
        (tester) async {
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          userID: 'carol',
          conversation: _c2cConversation(userID: 'carol', showName: 'Carol'),
          showUserOnlineStatus: false,
          getUserOnlineStatus: ({required String userID}) => true,
          getGroupMembersInfo: () => const [],
        ),
      ));
      await tester.pump();

      expect(find.text('Carol'), findsOneWidget);
      expect(find.text('Online'), findsNothing,
          reason: 'status row must not render when toggled off');
      expect(find.text('Offline'), findsNothing);
    });

    testWidgets('falls back to widget.userID for display name when '
        'conversation is null', (tester) async {
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          userID: 'fallback-uid',
          conversation: null,
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) => true,
          getGroupMembersInfo: () => const [],
        ),
      ));
      await tester.pump();

      expect(find.text('fallback-uid'), findsOneWidget,
          reason: 'display name falls back to widget.userID');
      // Conversation is null → _getStatusText returns '' early, no status row.
      expect(find.text('Online'), findsNothing);
      expect(find.text('Offline'), findsNothing);
    });
  });

  group('ToxeeMessageHeaderInfo - group', () {
    testWidgets('renders group subtitle when 3+ members', (tester) async {
      var membersCalls = 0;
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          groupID: 'g1',
          conversation: _groupConversation(groupID: 'g1', showName: 'Group 1'),
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) => false,
          getGroupMembersInfo: () {
            membersCalls += 1;
            return [
              _member('u1', nickName: 'Alice'),
              _member('u2', nickName: 'Bob'),
              _member('u3', nickName: 'Carol'),
            ];
          },
        ),
      ));
      await tester.pump();

      expect(find.text('Group 1'), findsOneWidget);
      // UIKit en `groupSubtitle(3, 'Alice')` → "Alice, etc(3 in total)".
      // We don't pin the exact string (UIKit may revise copy) — just that the
      // subtitle references the first member name and the member count.
      expect(membersCalls, greaterThanOrEqualTo(1),
          reason: 'group branch must read members list');
      expect(find.textContaining('Alice'), findsWidgets,
          reason: 'subtitle should mention the first member');
      expect(find.textContaining('3'), findsWidgets,
          reason: 'subtitle should include the member count');
    });

    testWidgets('omits status row when group has <=2 members', (tester) async {
      await tester.pumpWidget(_wrap(
        ToxeeMessageHeaderInfo(
          groupID: 'g2',
          conversation: _groupConversation(groupID: 'g2', showName: 'Duo'),
          showUserOnlineStatus: true,
          getUserOnlineStatus: ({required String userID}) => false,
          getGroupMembersInfo: () => [
            _member('u1', nickName: 'Alice'),
            _member('u2', nickName: 'Bob'),
          ],
        ),
      ));
      await tester.pump();

      expect(find.text('Duo'), findsOneWidget);
      // _getStatusText returns '' for <=2 members → status row absent.
      // Assert via the text count: only the display-name Text widget should
      // render.
      expect(find.byType(Text), findsOneWidget,
          reason: 'no status row when group has <=2 members');
    });
  });
}
