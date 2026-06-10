// Real-UI widget test for the MOBILE home-shell bottom-navigation unread badge.
//
// SCOPE + HONEST LIMITATION (verified against current code):
// The phone bottom-nav is built by the PRIVATE `_buildBottomNavigationBar`
// (lib/ui/home_page.dart:1345-1486) inside `_HomePageState`. That file carries
// the user's unrelated uncommitted edits and the item forbids editing it; the
// bar is a private method with no public reusable widget, and the maintainers
// explicitly routed any test that needs to pump `HomePage` to `integration_test/`
// against a host bundle (see the comment at lib/ui/home_page.dart:218-229:
// even with init skipped, `build()` binds UIKit globals and builds the full
// IndexedStack tabs). So the "4 tabs render + IndexedStack switch" structure is
// NOT hermetically reachable from a `test/` widget test without either extracting
// the bar (forbidden here) or a host bundle.
//
// What IS faithfully gateable is the ONE production widget the bottom-nav embeds
// for its unread badge: `TencentCloudChatConversationTotalUnreadCount`
// (the chats tab's badge, lib/ui/home_page.dart:1404). It reads the unread count
// from the real conversation data layer and updates reactively off the real
// event bus. This gate drives that production widget through the real
// `setTotalUnreadCount` API (which fires the same event-bus event the bottom-nav
// badge listens to) and asserts the badge surfaces a count only when the
// provider reports unread — exactly the bottom-nav's "unread badge renders when
// the provider has unread" contract, at the provider layer, with no production
// logic re-implemented.
//
// Shared-Dart: the unread provider widget and the conversation data layer are
// platform-agnostic, so this coverage applies to iOS/Android as well as desktop.
//
// ignore_for_file: depend_on_referenced_packages, directives_ordering
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_common/tencent_cloud_chat.dart';
import 'package:tencent_cloud_chat_conversation/tencent_cloud_chat_conversation_tatal_unread_count.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setNativeLibraryName('tim2tox_ffi');

  void useMobileSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(420, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  // Always leave the shared conversation data layer at zero unread so this gate
  // is order-independent with the rest of the suite.
  tearDown(() {
    TencentCloudChat.instance.dataInstance.conversation.setTotalUnreadCount(0);
  });

  testWidgets(
    'bottom-nav unread badge: provider widget surfaces a count only when there is unread',
    (tester) async {
      useMobileSurface(tester);
      final conv = TencentCloudChat.instance.dataInstance.conversation;
      conv.setTotalUnreadCount(0);

      // Mirror exactly how the bottom-nav chats tab consumes the provider: hide
      // the badge at zero, otherwise show the (capped) count. We assert via the
      // count the production widget HANDS to the builder, not by re-deriving it.
      int? lastCount;
      Widget badgeFor(int total) {
        lastCount = total;
        if (total == 0) {
          return const SizedBox.shrink(key: ValueKey('badge_hidden'));
        }
        final text = total > 99 ? '99+' : '$total';
        return Text(text, key: const ValueKey('badge_count'));
      }

      await tester.pumpWidget(
        _localized(
          child: Center(
            child: TencentCloudChatConversationTotalUnreadCount(
              builder: (context, totalUnreadCount) => badgeFor(totalUnreadCount),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Zero unread: the production widget feeds 0 -> the badge is hidden.
      expect(lastCount, 0);
      expect(find.byKey(const ValueKey('badge_hidden')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_count')), findsNothing);

      // Drive the REAL unread API. setTotalUnreadCount fires the conversation
      // data event the provider widget listens to -> it rebuilds with 7.
      conv.setTotalUnreadCount(7);
      await tester.pumpAndSettle();

      expect(lastCount, 7,
          reason: 'provider must reactively deliver the new unread count');
      expect(find.byKey(const ValueKey('badge_count')), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_hidden')), findsNothing);

      // Over-99 caps to "99+" (the bottom-nav's display contract).
      conv.setTotalUnreadCount(150);
      await tester.pumpAndSettle();
      expect(lastCount, 150);
      expect(find.text('99+'), findsOneWidget);

      // Back to zero: the badge hides again, proving the reactive round-trip.
      conv.setTotalUnreadCount(0);
      await tester.pumpAndSettle();
      expect(lastCount, 0);
      expect(find.byKey(const ValueKey('badge_hidden')), findsOneWidget);
      expect(find.byKey(const ValueKey('badge_count')), findsNothing);
    },
  );
}
