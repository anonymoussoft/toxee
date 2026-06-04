import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/home_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Future<BuildContext> _pumpL10nHarness(WidgetTester tester) async {
  BuildContext? capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: Scaffold(
        body: Builder(
          builder: (context) {
            capturedContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(capturedContext, isNotNull);
  return capturedContext!;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'conversation context menu exposes shipped pin/unpin/mark-read/delete keys',
    (tester) async {
      final context = await _pumpL10nHarness(tester);
      final l10n = AppLocalizations.of(context)!;
      final scheme = Theme.of(context).colorScheme;

      final unpinnedItems = buildConversationContextMenuItems(
        l10n: l10n,
        scheme: scheme,
        isPinned: false,
        hasUnread: true,
      );
      final unpinnedPinItem = unpinnedItems.first as PopupMenuItem<String>;
      final unpinnedMarkReadItem = unpinnedItems[1] as PopupMenuItem<String>;
      final unpinnedDeleteItem = unpinnedItems.last as PopupMenuItem<String>;

      expect(unpinnedPinItem.key, UiKeys.conversationContextMenuPinItem);
      expect(
        unpinnedMarkReadItem.key,
        UiKeys.conversationContextMenuMarkReadItem,
      );
      expect(unpinnedMarkReadItem.enabled, isTrue);
      expect(unpinnedDeleteItem.key, UiKeys.conversationContextMenuDeleteItem);

      final pinnedItems = buildConversationContextMenuItems(
        l10n: l10n,
        scheme: scheme,
        isPinned: true,
        hasUnread: false,
      );
      final pinnedToggleItem = pinnedItems.first as PopupMenuItem<String>;
      final pinnedMarkReadItem = pinnedItems[1] as PopupMenuItem<String>;

      expect(pinnedToggleItem.key, UiKeys.conversationContextMenuUnpinItem);
      expect(
        pinnedMarkReadItem.key,
        UiKeys.conversationContextMenuMarkReadItem,
      );
      expect(pinnedMarkReadItem.enabled, isFalse);
    },
  );

  testWidgets('delete conversation dialog exposes shipped confirm-button key', (
    tester,
  ) async {
    final context = await _pumpL10nHarness(tester);
    final dialog = buildDeleteConversationDialog(
      dialogCtx: context,
      l10n: AppLocalizations.of(context)!,
      scheme: Theme.of(context).colorScheme,
      conversationLabel: 'Alice',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: Builder(builder: (_) => dialog)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(UiKeys.deleteConversationConfirmButton), findsOneWidget);
  });
}
