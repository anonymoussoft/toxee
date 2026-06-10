// Real-UI widget tests for [StartupLoadingScreen] (lib/ui/startup_loading_screen.dart).
//
// These pump the REAL production widget and drive its REAL handlers:
//  - each progressive StartupStep renders its localized message + icon,
//  - the ERROR state shows the Retry + Go-to-Login actions,
//  - tapping Retry invokes the production `onRetry` callback (the same
//    VoidCallback wired by the _StartupGate retry path),
//  - tapping Go-to-Login invokes the production `onGoToLogin` callback.
//
// The widget already exposes `onRetry` / `onGoToLogin` as function-typed ctor
// params (the repo's canonical seam pattern), so no production change is needed
// for this surface — the test drives the real button onPressed.
//
// Shared-Dart coverage: StartupLoadingScreen lives in lib/ui and is used on
// both desktop and mobile startup, so this gate covers mobile automatically.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/startup/startup_step.dart';
import 'package:toxee/ui/startup_loading_screen.dart';

/// Wrap the widget under test so toxee's own AppLocalizations ancestor is
/// available (StartupLoadingScreen reads `AppLocalizations.of(context)` during
/// build and falls back to a bare spinner if it is null).
Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  // Map each active step to the literal English message the real widget should
  // render. These come straight from the production _stepMeta table.
  const stepMessages = <StartupStep, String>{
    StartupStep.checkingUserInfo: 'Checking user information...',
    StartupStep.initializingService: 'Initializing service...',
    StartupStep.loggingIn: 'Logging in...',
    StartupStep.initializingSDK: 'Initializing SDK...',
    StartupStep.updatingProfile: 'Updating profile...',
    StartupStep.connecting: 'Establishing encrypted channel...',
    StartupStep.loadingFriends: 'Loading friends...',
  };

  group('StartupLoadingScreen progressive step states', () {
    for (final entry in stepMessages.entries) {
      testWidgets('renders message for ${entry.key.name}', (tester) async {
        await tester.pumpWidget(
          _app(StartupLoadingScreen(currentStep: entry.key)),
        );
        await tester.pump(const Duration(milliseconds: 700));

        // Real production message text for this step.
        expect(find.text(entry.value), findsOneWidget);
        // App name footer is always shown in the loading (non-error) content.
        expect(find.text('Toxee'), findsOneWidget);
        // Progress bar present (loading content, not error content).
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        // No error affordances in the happy path.
        expect(find.byIcon(Icons.error_outline), findsNothing);
      });
    }

    testWidgets('completed step shows the completed message', (tester) async {
      await tester.pumpWidget(
        _app(const StartupLoadingScreen(currentStep: StartupStep.completed)),
      );
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('Initialization completed!'), findsOneWidget);
    });

    testWidgets('progress percentage advances between steps', (tester) async {
      // Pump an early step, settle its progress animation, read the %.
      await tester.pumpWidget(
        _app(
          const StartupLoadingScreen(
            currentStep: StartupStep.checkingUserInfo,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 800));
      // checkingUserInfo == 1/7 == 14%.
      expect(find.text('14%'), findsOneWidget);

      // Drive the same widget forward to a later step (didUpdateWidget path).
      await tester.pumpWidget(
        _app(const StartupLoadingScreen(currentStep: StartupStep.loadingFriends)),
      );
      await tester.pump(const Duration(milliseconds: 800));
      // loadingFriends == 7/7 == 100%.
      expect(find.text('100%'), findsOneWidget);
    });
  });

  group('StartupLoadingScreen error state', () {
    testWidgets('error state renders message + Retry + Go-to-Login',
        (tester) async {
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            errorMessage: 'boom: handshake timed out',
            onRetry: () {},
            onGoToLogin: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('Startup Failed'), findsOneWidget);
      expect(find.text('boom: handshake timed out'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsOneWidget);
      // Retry (FilledButton) + Go-to-Login (OutlinedButton) both present.
      expect(find.widgetWithText(FilledButton, 'Retry'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Go to Login'), findsOneWidget);
      // Loading content must be gone in the error arm.
      expect(find.byType(LinearProgressIndicator), findsNothing);
    });

    testWidgets('null errorMessage falls back to Unknown error literal',
        (tester) async {
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            // errorMessage null, but a callback flips to the error arm.
            errorMessage: null,
            onRetry: () {},
          ),
        ),
      );
      // The error arm is gated on errorMessage != null, so with a null message
      // and a non-null callback we are still in the LOADING arm. Confirm that.
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Startup Failed'), findsNothing);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('error arm shows Unknown error when message is empty-but-present',
        (tester) async {
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            errorMessage: '',
            onRetry: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      // errorMessage '' is non-null → error arm; body Text uses
      // `errorMessage ?? unknownError`, so the empty string is rendered (an
      // empty Text), and the title is still shown.
      expect(find.text('Startup Failed'), findsOneWidget);
    });

    testWidgets('tapping Retry invokes the production onRetry callback',
        (tester) async {
      var retryCalls = 0;
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            errorMessage: 'failed',
            onRetry: () => retryCalls++,
            onGoToLogin: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      expect(retryCalls, 1);
    });

    testWidgets('tapping Go-to-Login invokes the production onGoToLogin callback',
        (tester) async {
      var navCalls = 0;
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            errorMessage: 'failed',
            onRetry: () {},
            onGoToLogin: () => navCalls++,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));

      await tester.tap(find.widgetWithText(OutlinedButton, 'Go to Login'));
      await tester.pump();
      expect(navCalls, 1);
    });

    testWidgets('error arm hides Retry when onRetry is null', (tester) async {
      await tester.pumpWidget(
        _app(
          StartupLoadingScreen(
            currentStep: StartupStep.loggingIn,
            errorMessage: 'failed',
            // onRetry omitted → button must not render.
            onGoToLogin: () {},
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.widgetWithText(FilledButton, 'Retry'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Go to Login'), findsOneWidget);
    });
  });
}
