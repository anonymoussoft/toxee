// Real-UI widget tests for S95 — the prefs newer-than-app upgrade-required
// screen (lib/ui/upgrade_required_screen.dart).
//
// These pump the REAL [UpgradeRequiredScreen] and assert:
//  - the localized title + version-aware message body render,
//  - the system-update status chip renders,
//  - the primary "Update" action invokes its production handler.
//
// The production "Update" button calls `_openReleasesPage()` (a url_launcher
// `launchUrl`) which cannot complete under `flutter test` (no plugin binary).
// To drive the REAL button onPressed without a live browser we use the repo's
// canonical seam: an optional `onUpdate` function-typed ctor param that
// defaults to `_openReleasesPage`. The test injects a recorder; the production
// FilledButton.onPressed (`onUpdate ?? _openReleasesPage`) is what fires it.
//
// Shared-Dart coverage: UpgradeRequiredScreen is the cold-start gate on both
// desktop and mobile, so this widget-layer (L1) gate covers mobile too.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/upgrade_required_screen.dart';

/// Provide toxee's own AppLocalizations ancestor; the screen reads
/// `AppLocalizations.of(context)!` during build.
Widget _app(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );
}

void main() {
  testWidgets('renders title, version-aware message, and update chip',
      (tester) async {
    await tester.pumpWidget(
      _app(const UpgradeRequiredScreen(storedVersion: 99, currentVersion: 2)),
    );
    await tester.pump();

    expect(find.text('Please upgrade the app'), findsOneWidget);
    // The body interpolates the stored/current data versions (99 → 2).
    expect(
      find.text(
        'Your data was saved by a newer version of the app '
        '(data version: 99). This version supports up to 2. '
        'Please install the latest update to continue.',
      ),
      findsOneWidget,
    );
    // System-update status chip.
    expect(find.byIcon(Icons.system_update), findsOneWidget);
    // Primary action button labelled "Update".
    expect(find.widgetWithText(FilledButton, 'Update'), findsOneWidget);
  });

  testWidgets('message body reflects the actual version numbers passed',
      (tester) async {
    await tester.pumpWidget(
      _app(const UpgradeRequiredScreen(storedVersion: 7, currentVersion: 3)),
    );
    await tester.pump();
    expect(
      find.textContaining('data version: 7'),
      findsOneWidget,
    );
    expect(
      find.textContaining('supports up to 3'),
      findsOneWidget,
    );
  });

  testWidgets('tapping Update invokes the production update handler',
      (tester) async {
    var updateCalls = 0;
    await tester.pumpWidget(
      _app(
        UpgradeRequiredScreen(
          storedVersion: 99,
          currentVersion: 2,
          // Seam over the real _openReleasesPage() launchUrl handler.
          onUpdate: () async => updateCalls++,
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.widgetWithText(FilledButton, 'Update'));
    await tester.pump();
    expect(updateCalls, 1);
  });

  testWidgets('Update button is wired even without an injected handler',
      (tester) async {
    // With no seam, the real default handler (_openReleasesPage) is attached.
    // We cannot let launchUrl run under flutter_test, so we only assert the
    // button exists and is enabled (onPressed non-null) — proving the
    // production default path is wired, not the test seam.
    await tester.pumpWidget(
      _app(const UpgradeRequiredScreen(storedVersion: 99, currentVersion: 2)),
    );
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Update'),
    );
    expect(button.onPressed, isNotNull);
  });
}
