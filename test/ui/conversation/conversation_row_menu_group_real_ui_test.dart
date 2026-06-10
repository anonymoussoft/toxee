// Real-UI L1 gates for the NGC group conversation-row context-menu surfaces.
//
// Covers: S131 (menu surface — group), S132 (pin/unpin key flip — group),
// S133 (mark-read enabled/disabled — group), S134 (delete + confirm dialog —
// group).
//
// The menu builder (buildConversationContextMenuItems) and delete-dialog
// builder (buildDeleteConversationDialog) are @visibleForTesting seams
// exported from lib/ui/home_page.dart.  They are stateless constructors:
// they receive l10n/scheme/state as arguments and return the PopupMenuEntry
// list or AlertDialog widget.  No SDK call is required to drive them, so
// these tests run hermetically without the tim2tox FFI native library.
//
// The conversation-item TAP test (S131 open surface) sets up the shared
// TencentCloudChat.instance.dataInstance.conversation data layer — the same
// approach the conference_conversation_row_real_ui_test.dart uses for S159.
//
// Mobile parity: all surfaces here are shared Dart (lib/ui/home_page.dart,
// lib/sdk_fake/fake_managers.dart, lib/i18n/).  No platform-specific split.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_common/components/tencent_cloud_chat_components_utils.dart';
import 'package:tencent_cloud_chat_common/cross_platforms_adapter/tencent_cloud_chat_screen_adapter.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_builders.dart';
import 'package:tencent_cloud_chat_conversation/widgets/tencent_cloud_chat_conversation_item.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tencent_cloud_chat_sdk/native_im/bindings/native_library_manager.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home_page.dart'
    show buildConversationContextMenuItems, buildDeleteConversationDialog;
import 'package:toxee/ui/testing/ui_keys.dart';

// ---------------------------------------------------------------------------
// Harness helpers (copied from conference_conversation_row_real_ui_test.dart;
// do NOT import private helpers from other test files)
// ---------------------------------------------------------------------------

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

/// Pump a minimal localized tree and capture the AppLocalizations +
/// ColorScheme pair so production menu/dialog builders can be exercised.
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

/// Build the menu items for the given pin/unread state and return their keys.
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

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // Inform the SDK layer which native lib name to expect.  Required for the
  // conversation-item tap test that seeds TencentCloudChat data; does not load
  // the native library at the unit-test level.
  setNativeLibraryName('tim2tox_ffi');

  // S131 — NGC group conversation-row item tap selects the conversation.
  //
  // Tapping the group row sets currentConversation in the shared data layer,
  // proving the SAME tap-to-select path works for group rows.  The
  // conversation-row tap handler is type-agnostic (type:2 = group).
  testWidgets(
    'S131 NGC group conversation item tap selects it (sets currentConversation)',
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

      const tileKey =
          ValueKey('conversation_list_item:group_tox_ngc_131');
      await tester.pumpWidget(
        _appLocalized(
          Builder(
            builder: (context) {
              TencentCloudChatIntl().init(context);
              return KeyedSubtree(
                key: tileKey,
                child: TencentCloudChatConversationItem(
                  conversation: V2TimConversation(
                    conversationID: 'group_tox_ngc_131',
                    type: 2,
                    groupID: 'tox_ngc_131',
                    showName: 'NGC Group 131',
                  ),
                  isOnline: false,
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        conv.currentConversation?.conversationID,
        isNot('group_tox_ngc_131'),
      );
      await tester.tap(find.byKey(tileKey));
      await tester.pumpAndSettle();
      expect(
        conv.currentConversation?.conversationID,
        'group_tox_ngc_131',
        reason: 'tapping the group row should select the conversation',
      );
    },
  );

  // S131 — NGC group conversation-row context menu surfaces expected items.
  //
  // The menu builder is shared across C2C, group, and conference rows.  This
  // gate asserts the group-flavored call (type:2, isPinned:false, hasUnread:true)
  // exposes pin + mark-read (enabled) + delete and does NOT expose unpin.
  testWidgets(
    'S131 NGC group conversation-row menu surfaces pin / mark-read / delete',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);
      final keys = _menuKeys(l10n, scheme, isPinned: false, hasUnread: true);

      expect(keys, contains(UiKeys.conversationContextMenuPinItem));
      expect(keys, contains(UiKeys.conversationContextMenuMarkReadItem));
      expect(keys, contains(UiKeys.conversationContextMenuDeleteItem));
      // Unpin is absent when the group is not pinned.
      expect(keys, isNot(contains(UiKeys.conversationContextMenuUnpinItem)));
    },
  );

  // S131 (variant) — pinned group row shows unpin, not pin.
  testWidgets(
    'S131 NGC group conversation-row menu shows unpin (not pin) when pinned',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);
      final keys = _menuKeys(l10n, scheme, isPinned: true, hasUnread: false);

      expect(keys, contains(UiKeys.conversationContextMenuUnpinItem));
      expect(keys, isNot(contains(UiKeys.conversationContextMenuPinItem)));
      // Mark-read and delete are always present.
      expect(keys, contains(UiKeys.conversationContextMenuMarkReadItem));
      expect(keys, contains(UiKeys.conversationContextMenuDeleteItem));
    },
  );

  // S132 — pin/unpin item key flips with isPinned state for NGC groups.
  //
  // The pin/unpin key flip is identical for C2C and group rows; both use the
  // same buildConversationContextMenuItems builder.  This is the group-specific
  // regression canary: if the group-flavored menu were ever customized and the
  // key flip broke, this test catches it.
  testWidgets(
    'S132 NGC group conversation-row menu pin item key flips with pinned state',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      // Unpinned → Pin key present, Unpin absent.
      final unpinnedKeys =
          _menuKeys(l10n, scheme, isPinned: false, hasUnread: false);
      expect(
        unpinnedKeys,
        contains(UiKeys.conversationContextMenuPinItem),
      );
      expect(
        unpinnedKeys,
        isNot(contains(UiKeys.conversationContextMenuUnpinItem)),
      );

      // Pinned → Unpin key present, Pin absent.
      final pinnedKeys =
          _menuKeys(l10n, scheme, isPinned: true, hasUnread: false);
      expect(
        pinnedKeys,
        contains(UiKeys.conversationContextMenuUnpinItem),
      );
      expect(
        pinnedKeys,
        isNot(contains(UiKeys.conversationContextMenuPinItem)),
      );
    },
  );

  // S132 (value check) — pin and unpin items carry value:'pin' for the group
  // toggle dispatch, identical to the C2C case.
  testWidgets(
    'S132 NGC group pin and unpin items both carry value:pin (toggle dispatch)',
    (tester) async {
      final (l10n, scheme) = await _captureL10nScheme(tester);

      final pinItem = buildConversationContextMenuItems(
        l10n: l10n,
        scheme: scheme,
        isPinned: false,
        hasUnread: false,
      ).first as PopupMenuItem<String>;

      final unpinItem = buildConversationContextMenuItems(
        l10n: l10n,
        scheme: scheme,
        isPinned: true,
        hasUnread: false,
      ).first as PopupMenuItem<String>;

      expect(pinItem.value, 'pin',
          reason: 'pin item value must be "pin" for group dispatch');
      expect(unpinItem.value, 'pin',
          reason: 'unpin item value must be "pin" for the same group toggle');
    },
  );

  // S133 — mark-read item is enabled only when the group has unread.
  testWidgets(
    'S133 NGC group mark-read item is enabled when hasUnread, disabled otherwise',
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
          reason: 'mark-read must be enabled when the group has unread');
      expect(markReadItem(false).enabled, isFalse,
          reason: 'mark-read must be disabled when there is no unread');
    },
  );

  // S134 — delete item opens the keyed confirm dialog for an NGC group.
  //
  // The delete dialog builder is shared with C2C.  This gate asserts that for
  // a group conversation label the dialog still mounts with the keyed confirm
  // button and names the group in the body.
  testWidgets(
    'S134 NGC group delete-confirm dialog mounts with keyed confirm button',
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
                    conversationLabel: 'NGC Group 134',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Dialog not yet shown.
      expect(find.byKey(UiKeys.deleteConversationConfirmButton), findsNothing);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsOneWidget,
        reason:
            'group delete-confirm dialog must mount its keyed confirm button',
      );
      expect(
        find.textContaining('NGC Group 134'),
        findsOneWidget,
        reason: 'the confirm dialog body must name the NGC group',
      );
    },
  );

  // S134 — confirming the group delete dialog dismisses it.
  testWidgets(
    'S134 NGC group delete-confirm dialog confirm button dismisses the dialog',
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
                    conversationLabel: 'NGC Group 134b',
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsOneWidget,
      );

      // Tap confirm — dialog should dismiss.
      await tester.tap(find.byKey(UiKeys.deleteConversationConfirmButton));
      await tester.pumpAndSettle();

      expect(
        find.byKey(UiKeys.deleteConversationConfirmButton),
        findsNothing,
        reason: 'confirm button tap should dismiss the group delete dialog',
      );
    },
  );
}
