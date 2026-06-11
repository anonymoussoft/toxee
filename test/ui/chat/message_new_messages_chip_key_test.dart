import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_builders.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_list/message_list.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_list_view/message_list/message_list_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('received-new-messages chip exposes a stable tap key', (
    tester,
  ) async {
    final controller = MessageListController();
    var tapped = false;
    final provider = TencentCloudChatMessageSeparateDataProvider()
      ..messageBuilders = TencentCloudChatMessageBuilders(
        messageDynamicButtonBuilder:
            ({key, required widgets, required data, required methods}) =>
                TextButton(
                  onPressed: () => tapped = true,
                  child: Text(data.text ?? ''),
                ),
      );

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        localizationsDelegates: const [
          TencentCloudChatLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return TencentCloudChatMessageDataProviderInherited(
                dataProvider: provider,
                child: SizedBox(
                  width: 480,
                  height: 360,
                  child: MessageList(
                    controller: controller,
                    msgCount: 1,
                    onMsgKey: (_) => 'existing-message',
                    itemBuilder: (_, __) => const SizedBox(
                      height: 48,
                      child: Text('existing-message'),
                    ),
                    determineIsLatestReadMessage: (_) => (false, false),
                    onLoadToLatestReadMessage: () async {},
                    messagesMentionedMe: const [],
                    onLoadToLatestMessageMentionedMe: () async {},
                    closeSticker: () {},
                    showUnreadMsgButton: false,
                    showScrollToTopButton: false,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(controller.stateObj, isNotNull);
    controller.stateObj!.newMessageCount.value = 1;
    await tester.pump();

    final chip = find.byKey(const ValueKey('new_messages_chip'));
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    await tester.pump();
    expect(tapped, isTrue);
  });
}
