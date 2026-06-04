import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/search/custom_search.dart';
import 'package:toxee/ui/search/search_chat_history_window.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _harness(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

Future<void> _pumpSettled(WidgetTester tester, Widget child) async {
  await tester.binding.setSurfaceSize(const Size(1280, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_harness(child));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

V2TimMessage _textMessage({required String msgId, required String text}) {
  return V2TimMessage.fromJson(<String, dynamic>{
    'message_conv_type': 1,
    'message_conv_id': 'friend_123',
    'message_sender': '',
    'message_client_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_server_time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    'message_msg_id': msgId,
    'message_elem_array': <Map<String, dynamic>>[
      V2TimTextElem(text: text).toJson(),
    ],
  });
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('search anchors', () {
    testWidgets('CustomSearch exposes a stable search field key', (
      tester,
    ) async {
      await _pumpSettled(tester, const CustomSearch());

      expect(find.byKey(UiKeys.messageSearchField), findsOneWidget);
    });

    testWidgets(
      'SearchChatHistoryWindow exposes stable result and message row keys',
      (tester) async {
        final result = TencentCloudChatSearchResultItemData(
          conversationID: 'c2c_friend_123',
          showName: 'Friend 123',
          messageList: <V2TimMessage>[
            _textMessage(msgId: 'msg-1', text: 'pizza keyword'),
          ],
        );

        await _pumpSettled(
          tester,
          SearchChatHistoryWindow(
            initialKeyword: 'pizza',
            messageSearchResults: <TencentCloudChatSearchResultItemData>[
              result,
            ],
            initialSelectedResult: result,
            onNavigateToMessage:
                ({
                  String? userID,
                  String? groupID,
                  V2TimMessage? targetMessage,
                }) {},
          ),
        );

        expect(find.byKey(UiKeys.messageSearchField), findsOneWidget);
        expect(
          find.byKey(UiKeys.searchResultMessage('c2c_friend_123')),
          findsOneWidget,
        );
        expect(
          find.byKey(UiKeys.searchHistoryMessage('msg-1')),
          findsOneWidget,
        );
      },
    );
  });
}
