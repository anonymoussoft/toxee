// Real-UI widget tests for S10's UI half — the Home connection-status banner
// and the send-error banner.
//
//  - [ConnectionStatusBanner] (lib/ui/widgets/connection_status_banner.dart) is
//    the production global connection banner. Its production status SOURCE is a
//    `Stream<bool>` of `isConnected` ticks — exactly `FfiChatService.isConnected`
//    + `FfiChatService.connectionStatusStream` (per the widget's own doc). This
//    gate drives that real stream: offline tick → the offline banner appears;
//    online tick → it collapses (SizedBox.shrink). Tapping the offline banner
//    invokes the production `onRetry`.
//
//  - [ErrorBanner] (lib/ui/widgets/error_banner.dart) is the send-error banner.
//    This gate asserts the message renders, the production Retry handler fires,
//    and the production Dismiss handler fires.
//
// The banners are deliberately NOT auto-mounted into HomePage (see the widget
// doc + S10 note); the production status source is the stream they consume, so
// driving the stream IS driving the production source. We avoid touching
// home_page.dart (it carries unrelated uncommitted edits).
//
// Shared-Dart coverage: both banner widgets live in lib/ui/widgets and are
// platform-agnostic, so this widget-layer (L1) gate covers mobile too.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/widgets/connection_status_banner.dart';
import 'package:toxee/ui/widgets/error_banner.dart';

/// Host that disables animations so the AnimatedSwitcher in the connection
/// banner settles deterministically (the widget collapses its switch duration
/// to Duration.zero when reduce-motion is on). Provides toxee's own
/// AppLocalizations (ErrorBanner reads `AppLocalizations.of(context)` for its
/// a11y label, with a hardcoded fallback).
Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: child,
      ),
    ),
  );
}

void main() {
  group('ConnectionStatusBanner (S10 UI half)', () {
    testWidgets('offline tick shows the offline banner; reconnect collapses it',
        (tester) async {
      final controller = StreamController<bool>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(
          ConnectionStatusBanner(
            statusStream: controller.stream,
            initialIsConnected: true, // start online → no banner
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Online to start: banner collapsed.
      expect(find.byKey(const ValueKey('online')), findsOneWidget);
      expect(find.byKey(const ValueKey('offline')), findsNothing);
      expect(find.text('Disconnected'), findsNothing);

      // Drive the PRODUCTION status source offline.
      controller.add(false);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('offline')), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.byIcon(Icons.cloud_off), findsOneWidget);

      // Reconnect: banner disappears again.
      controller.add(true);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('online')), findsOneWidget);
      expect(find.byKey(const ValueKey('offline')), findsNothing);
      expect(find.text('Disconnected'), findsNothing);
    });

    testWidgets('no initial data renders the connecting state', (tester) async {
      final controller = StreamController<bool>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(ConnectionStatusBanner(statusStream: controller.stream)),
      );
      // The connecting banner hosts an indeterminate LinearProgressIndicator
      // (a never-settling ticker), so pumpAndSettle would time out — pump a
      // fixed frame instead.
      await tester.pump();

      expect(find.byKey(const ValueKey('connecting')), findsOneWidget);
      expect(find.text('Connecting to Tox network…'), findsOneWidget);
    });

    testWidgets('tapping the offline banner invokes the production onRetry',
        (tester) async {
      var retryCalls = 0;
      final controller = StreamController<bool>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(
          ConnectionStatusBanner(
            statusStream: controller.stream,
            initialIsConnected: false, // start offline → banner shown
            onRetry: () => retryCalls++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('offline')), findsOneWidget);
      // The retry refresh icon shows only when onRetry is wired.
      expect(find.byIcon(Icons.refresh), findsOneWidget);

      // Tap the banner body (InkWell wraps onRetry).
      await tester.tap(find.byKey(const ValueKey('offline')));
      await tester.pump();
      expect(retryCalls, 1);
    });

    testWidgets('offline banner without onRetry hides the refresh affordance',
        (tester) async {
      final controller = StreamController<bool>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(
          ConnectionStatusBanner(
            statusStream: controller.stream,
            initialIsConnected: false,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('offline')), findsOneWidget);
      expect(find.byIcon(Icons.refresh), findsNothing);
    });

    testWidgets('a dead status stream surfaces offline-unknown', (tester) async {
      final controller = StreamController<bool>.broadcast();
      addTearDown(controller.close);

      await tester.pumpWidget(
        _app(
          ConnectionStatusBanner(
            statusStream: controller.stream,
            initialIsConnected: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      controller.addError(StateError('stream died'));
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('offline-error')), findsOneWidget);
      expect(find.text('Network status unavailable'), findsOneWidget);
    });
  });

  group('ErrorBanner (send-error banner)', () {
    testWidgets('renders the error message', (tester) async {
      await tester.pumpWidget(
        _app(const ErrorBanner(message: 'Failed to send message')),
      );
      await tester.pump();
      expect(find.text('Failed to send message'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
    });

    testWidgets('tapping Retry invokes the production onRetry', (tester) async {
      var retryCalls = 0;
      await tester.pumpWidget(
        _app(
          ErrorBanner(
            message: 'Send failed',
            onRetry: () => retryCalls++,
          ),
        ),
      );
      await tester.pump();

      expect(find.widgetWithText(TextButton, 'Retry'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Retry'));
      await tester.pump();
      expect(retryCalls, 1);
    });

    testWidgets('tapping Dismiss invokes the production onDismiss',
        (tester) async {
      var dismissCalls = 0;
      await tester.pumpWidget(
        _app(
          ErrorBanner(
            message: 'Send failed',
            onDismiss: () => dismissCalls++,
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.close), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      expect(dismissCalls, 1);
    });

    testWidgets('omits Retry / Dismiss affordances when handlers are null',
        (tester) async {
      await tester.pumpWidget(
        _app(const ErrorBanner(message: 'Send failed')),
      );
      await tester.pump();
      expect(find.widgetWithText(TextButton, 'Retry'), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });
  });
}
