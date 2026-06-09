// Conference real-UI gates for the desktop composer SEND path (S160/S181/S182).
// These reuse the proven chat_core_real_ui_test.dart harness: the fork composer
// is ExtendedTextField (extended_text_field), whose editable is NOT the stock
// EditableText, so text is delivered via tester.testTextInput and submitted with
// a real Enter key event through the actual RawKeyEvent handler — the exact send
// path the marionette MCP harness cannot inject on desktop.
//
// Scope: the composer SEND callback is what these gates drive (the local send
// leg). The cross-process RECEIVE of a conference message (the peer seeing it) is
// the legacy conference transport — covered by the `conference_message`
// two-process real-UI pair gate (drive_real_ui_pair.dart), not reproducible in a
// single-process widget test.
//
// Mobile parity: the desktop Enter-to-send composer is the DESKTOP surface; the
// mobile composer (tencent_cloud_chat_message_input_mobile.dart) send-button path
// is covered by chat_core_real_ui_test.dart's emoji/mobile gates and the shared
// sendTextMessage callback wired in home_page_bootstrap.dart.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:extended_text_field/extended_text_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:tencent_cloud_chat_common/components/component_config/tencent_cloud_chat_message_common_defines.dart';
import 'package:tencent_cloud_chat_common/components/components_definition/tencent_cloud_chat_component_builder_definitions.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data.dart';
import 'package:tencent_cloud_chat_message/model/tencent_cloud_chat_message_separate_data_notifier.dart';
import 'package:tencent_cloud_chat_message/tencent_cloud_chat_message_input/desktop/tencent_cloud_chat_message_input_desktop.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';

Widget _localized({required Widget child}) {
  return MaterialApp(
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
          return child;
        },
      ),
    ),
  );
}

MessageInputBuilderMethods _stubMethods(List<String> sentSink) {
  return MessageInputBuilderMethods(
    sendTextMessage: ({required String text, List<String>? mentionedUsers}) {
      sentSink.add(text);
    },
    sendImageMessage: ({String? imagePath, String? imageName, dynamic inputElement}) {},
    sendVideoMessage: ({String? videoPath, dynamic inputElement}) {},
    sendFileMessage: ({String? filePath, String? fileName, dynamic inputElement}) {},
    sendVoiceMessage: ({required String voicePath, required int duration}) {},
    onChooseGroupMembers: () async => <V2TimGroupMemberFullInfo>[],
    controller: Object(),
    clearRepliedMessage: () {},
    setDesktopMentionBoxPositionX: (_) {},
    setDesktopMentionBoxPositionY: (_) {},
    setActiveMentionIndex: (_) {},
    setCurrentFilteredMembersListForMention: (_) {},
    desktopInputMemberSelectionPanelScroll: AutoScrollController(),
    messageAttachmentOptionsBuilder: Object(),
    closeSticker: () {},
  );
}

// Conference-framed input data: a conference show name + a populated group
// member list (group/AVChatRoom shape). MessageInputBuilderData carries no
// groupID field — the desktop Enter-to-send path itself does not branch on
// conversation type, so this drives the SAME real send callback a conference
// chat uses (the type-agnostic local send leg; the conference transport is the
// two-process leg).
MessageInputBuilderData _confData() {
  return MessageInputBuilderData(
    userID: 'tox_conf_composer',
    attachmentOptions: const [],
    inSelectMode: false,
    enableReplyWithMention: false,
    status: TencentCloudChatMessageInputStatus.canSendMessage,
    selectedMessages: const [],
    desktopMentionBoxPositionX: 0,
    desktopMentionBoxPositionY: 0,
    isGroupAdmin: false,
    activeMentionIndex: -1,
    currentFilteredMembersListForMention: const [],
    groupMemberList: <V2TimGroupMemberFullInfo>[
      V2TimGroupMemberFullInfo(userID: 'alice', nickName: 'Alice'),
      V2TimGroupMemberFullInfo(userID: 'bob', nickName: 'Bob'),
    ],
    currentConversationShowName: 'Design Conference',
    hasStickerPlugin: false,
    stickerPluginInstance: null,
  );
}

Future<Finder> _pumpComposer(WidgetTester tester, List<String> sent) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final provider = TencentCloudChatMessageSeparateDataProvider();
  await tester.pumpWidget(
    _localized(
      child: TencentCloudChatMessageDataProviderInherited(
        dataProvider: provider,
        child: TencentCloudChatMessageInputDesktop(
          inputData: _confData(),
          inputMethods: _stubMethods(sent),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  final field = find.byType(ExtendedTextField);
  expect(field, findsWidgets, reason: 'the conference composer should render');
  return field;
}

// Focus the field, type [text], submit with a real Enter (no shift).
Future<void> _typeAndEnter(
  WidgetTester tester,
  Finder field,
  String text,
) async {
  await tester.tap(field.first);
  await tester.pump();
  tester.testTextInput.enterText(text);
  await tester.pump();
  await tester.sendKeyEvent(LogicalKeyboardKey.enter);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  // S160 — composer focus, type, send: Enter drives the real send callback;
  // typing alone does not (non-vacuous).
  testWidgets(
    'S160 conference composer: typing + Enter invokes the real send path',
    (tester) async {
      final sent = <String>[];
      final field = await _pumpComposer(tester, sent);

      await tester.tap(field.first);
      await tester.pump();
      tester.testTextInput.enterText('conf-hello-160');
      await tester.pump();
      expect(sent, isEmpty, reason: 'typing alone must not send');

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      // Exact cardinality: exactly one send, exactly the typed payload (a
      // `contains` check would pass on a duplicate-send regression).
      expect(sent, equals(['conf-hello-160']),
          reason: 'Enter must drive the conference composer send callback once');
    },
  );

  // S181 — realtime delivery (local send leg): the unique payload is carried by
  // the real send callback. The peer-side receive is the two-process leg.
  testWidgets(
    'S181 conference composer sends a unique payload through the real send path',
    (tester) async {
      final sent = <String>[];
      final field = await _pumpComposer(tester, sent);

      const payload = 'conf-realtime-181-Zx9';
      await _typeAndEnter(tester, field, payload);

      expect(sent, equals([payload]),
          reason: 'the real send path must carry exactly the typed conference '
              'payload (the local leg of realtime delivery)');
    },
  );

  // S182 — alternating burst: repeated focus/type/send cycles all land in order
  // and the composer stays stable.
  testWidgets(
    'S182 conference composer burst: repeated sends all land in order and the '
    'composer stays stable',
    (tester) async {
      final sent = <String>[];
      final field = await _pumpComposer(tester, sent);

      const payloads = [
        'conf-burst-1',
        'conf-burst-2',
        'conf-burst-3',
        'conf-burst-4',
      ];
      for (final p in payloads) {
        await _typeAndEnter(tester, field, p);
      }

      expect(sent, equals(payloads),
          reason: 'every burst message must land via the real send path, in order');
      // The composer survives the burst (still rendered + usable).
      expect(find.byType(ExtendedTextField), findsWidgets,
          reason: 'the composer must remain stable after a send burst');
    },
  );
}
