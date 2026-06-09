// Conference real-UI gates for the conversation-row surfaces shared with
// groups/C2C: opening a conference conversation (S159), the conversation-row
// context menu + delete-confirm dialog (S161-S164, toxee's @visibleForTesting
// builders in home_page.dart) and the conference search result → open path
// (S165, via the real SearchChatHistoryWindow with an injected navigate hook).
//
// These layers are explicitly type-agnostic in production (S161: "the row/menu
// layer is shared with groups and C2C"); the conference framing is that a
// conference conversation/row reuses exactly these surfaces. The gates drive the
// REAL production builders/widgets.
//
// Mobile parity: all surfaces here are shared Dart (no platform split).
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_common/chat_sdk/components/tencent_cloud_chat_search_sdk.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home_page.dart'
    show buildConversationContextMenuItems, buildDeleteConversationDialog;
import 'package:toxee/ui/search/search_chat_history_window.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// Harness with the toxee AppLocalizations delegate (the conversation context
// menu + delete dialog read their copy from it).
Widget _appLocalized(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

// Captures a real localizations + colorScheme pair so the production
// menu-builder (buildConversationContextMenuItems) can be invoked and its
// returned entries inspected directly. PopupMenuItem cannot be rendered outside
// a menu, and the returned list's keys/enabled flags are exactly what
// production's showMenu (home_page.dart:1606) consumes.
Future<(AppLocalizations, ColorScheme)> _captureL10nScheme(
    WidgetTester tester) async {
  late AppLocalizations l10n;
  late ColorScheme scheme;
  await tester.pumpWidget(
    _appLocalized(
      Builder(
        builder: (ctx) {
          l10n = AppLocalizations.of(ctx)!;
          scheme = Theme.of(ctx).colorScheme;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  await tester.pump();
  return (l10n, scheme);
}

Set<Key> _menuKeys(
  AppLocalizations l10n,
  ColorScheme scheme, {
  required bool isPinned,
  required bool hasUnread,
}) {
  return buildConversationContextMenuItems(
    l10n: l10n,
    scheme: scheme,
    isPinned: isPinned,
    hasUnread: hasUnread,
  ).map((e) => e.key).whereType<Key>().toSet();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  // S159 — open a conference conversation from the chats list: tapping the
  // (group-typed) conversation item selects it (sets currentConversation), the
  // same real desktop open path the chat list uses.
  testWidgets(
    'S159 conference conversation item tap selects it (sets currentConversation)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      TencentCloudChatScreenAdapter.deviceScreenType = DeviceScreenType.desktop;
      TencentCloudChatScreenAdapter.hasInitialized = true;
      addTearDown(() {
        TencentCloudChatScreenAdapter.deviceScreenType = null;
        TencentCloudChatScreenAdapter.hasInitialized = false;
      });

      final data = TencentCloudChat.instance.dataInstance;
      final conv = data.conversation;
      data.basic.usedComponents = [TencentCloudChatComponentsEnum.message];
      conv.conversationConfig.setConfigs(forceDesktopLayout: true);
      conv.conversationBuilder = TencentCloudChatConversationBuilders();
      conv.conversationEventHandlers = null;
      conv.currentConversation = null;
      addTearDown(() {
        conv.conversationBuilder = null;
        conv.conversationEventHandlers = null;
        conv.currentConversation = null;
        conv.conversationConfig.setConfigs(forceDesktopLayout: false);
        data.basic.usedComponents = [];
      });

      const tileKey = ValueKey('conversation_list_item:group_tox_conf_159');
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return KeyedSubtree(
                key: tileKey,
                child: TencentCloudChatConversationItem(
                  conversation: V2TimConversation(
                    conversationID: 'group_tox_conf_159',
                    type: 2,
                    groupID: 'tox_conf_159',
                    showName: 'Conference 159',
                  ),
                  isOnline: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(conv.currentConversation?.conversationID,
          isNot('group_tox_conf_159'));
      await tester.tap(find.byKey(tileKey));
      await tester.pumpAndSettle();
      expect(conv.currentConversation?.conversationID, 'group_tox_conf_159',
          reason: 'tapping the conference row should select the conversation');
    },
  );

  // S161 — the shared conversation-row context menu surfaces the expected
  // conversation actions (pin, mark-read, delete) for a conference row.
  testWidgets(
    'S161 conference conversation-row menu surfaces pin / mark-read / delete',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);
      final keys = _menuKeys(l10n, scheme, isPinned: false, hasUnread: true);

      expect(keys, contains(UiKeys.conversationContextMenuPinItem));
      expect(keys, contains(UiKeys.conversationContextMenuMarkReadItem));
      expect(keys, contains(UiKeys.conversationContextMenuDeleteItem));
    },
  );

  // S162 — pin / unpin: the menu's first item flips between the pin and unpin
  // keys with the conversation's pinned state.
  testWidgets(
    'S162 conference conversation-row menu pin item flips with pinned state',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      // Unpinned → the Pin action is offered.
      final unpinned = _menuKeys(l10n, scheme, isPinned: false, hasUnread: false);
      expect(unpinned, contains(UiKeys.conversationContextMenuPinItem));
      expect(unpinned, isNot(contains(UiKeys.conversationContextMenuUnpinItem)));

      // Pinned → the Unpin action is offered instead.
      final pinned = _menuKeys(l10n, scheme, isPinned: true, hasUnread: false);
      expect(pinned, contains(UiKeys.conversationContextMenuUnpinItem));
      expect(pinned, isNot(contains(UiKeys.conversationContextMenuPinItem)));
    },
  );

  // S163 — mark-read: the mark-read item is enabled only when the conference
  // conversation has unread.
  testWidgets(
    'S163 conference conversation-row mark-read item is enabled only with unread',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      PopupMenuItem<String> markReadItem(bool hasUnread) =>
          buildConversationContextMenuItems(
            l10n: l10n,
            scheme: scheme,
            isPinned: false,
            hasUnread: hasUnread,
          ).firstWhere(
            (e) => e.key == UiKeys.conversationContextMenuMarkReadItem,
          ) as PopupMenuItem<String>;

      expect(markReadItem(true).enabled, isTrue,
          reason: 'mark-read must be enabled when the conference has unread');
      expect(markReadItem(false).enabled, isFalse,
          reason: 'mark-read must be disabled when there is no unread');
    },
  );

  // S164 — delete + confirm: the keyed delete-confirm dialog mounts for a
  // conference row label.
  testWidgets(
    'S164 conference conversation-row delete opens the keyed confirm dialog',
    (tester) async {
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (outer) => Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: outer,
                  builder: (dialogCtx) => buildDeleteConversationDialog(
                    dialogCtx: dialogCtx,
                    l10n: AppLocalizations.of(dialogCtx)!,
                    scheme: Theme.of(dialogCtx).colorScheme,
                    conversationLabel: 'Conference 164',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.deleteConversationConfirmButton), findsNothing);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.byKey(UiKeys.deleteConversationConfirmButton), findsOneWidget,
          reason: 'the conference delete-confirm dialog must mount its keyed confirm');
      expect(find.textContaining('Conference 164'), findsOneWidget,
          reason: 'the confirm dialog must name the conference being deleted');
    },
  );

  // S165 — search result opens the target conference conversation: the real
  // SearchChatHistoryWindow routes a tapped conference message result to
  // onNavigateToMessage(groupID: <gidC>).
  testWidgets(
    'S165 tapping a conference message search result navigates to the '
    'conference (groupID)',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final result = TencentCloudChatSearchResultItemData(
        conversationID: 'group_tox_conf_165',
        groupID: 'tox_conf_165',
        showName: 'Conference 165',
        messageList: [
          V2TimMessage(
            msgID: 'cm1',
            isSelf: false,
            // nickName feeds the row's sender-name render (getShowName falls back
            // to message.sender! otherwise, which a bare message lacks).
            nickName: 'Conf Sender',
            sender: 'conf_sender',
            elemType: MessageElemType.V2TIM_ELEM_TYPE_TEXT,
            timestamp: 1700000000,
          ),
        ],
      );

      String? navUserID;
      String? navGroupID;
      void capture({String? userID, String? groupID, V2TimMessage? targetMessage}) {
        navUserID = userID;
        navGroupID = groupID;
      }

      await tester.pumpWidget(
        _appLocalized(
          Navigator(
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SearchChatHistoryWindow(
                // Empty keyword → every seeded message passes the filter, so the
                // conference result is selectable without depending on message text.
                initialKeyword: '',
                messageSearchResults: [result],
                initialSelectedResult: result,
                onNavigateToMessage: capture,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Desktop layout: left = the conference conversation row, right = its
      // message rows. The message row carries the exact production key
      // UiKeys.searchHistoryMessage(msgID) (search_chat_history_window.dart:606).
      final messageRow = find.byKey(UiKeys.searchHistoryMessage('cm1'));
      expect(messageRow, findsOneWidget,
          reason: 'the selected conference result should render its keyed message row');

      await tester.tap(messageRow);
      await tester.pumpAndSettle();

      expect(navGroupID, 'tox_conf_165',
          reason: 'tapping the conference search result must navigate to the '
              'conference groupID');
      expect(navUserID, isNull,
          reason: 'a conference result must navigate by groupID, not userID');
    },
  );
}
