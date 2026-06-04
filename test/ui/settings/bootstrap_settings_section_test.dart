// Widget tests for [BootstrapSettingsSection].
//
// This section is shared between the login-time settings page and the
// post-login settings page; the `service` parameter is null in the login-mode
// flow. We exercise the **service: null** case because it doesn't touch
// FFI / `FfiChatService`, which keeps the test hermetic.
//
// Covered behaviors:
//   1. Initial render at mode='auto' shows the three RadioListTile options on
//      desktop (the test process inherits a desktop classification on macOS),
//      with 'auto' selected.
//   2. Switching to manual via RadioListTile persists the mode in Prefs and
//      reveals the "Manual node input" affordance.
//   3. Tapping the "Manual node input" expand button toggles the manual host
//      / port / pubkey input row.
//   4. With pre-seeded bootstrap_node_* prefs, the "current node" tile shows
//      the seeded host:port string.

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/bootstrap_settings_section.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

Future<void> _initPrefs([Map<String, Object> seed = const {}]) async {
  SharedPreferences.setMockInitialValues(seed);
  final prefs = await SharedPreferences.getInstance();
  await Prefs.initialize(prefs);
}

Widget _harness({Widget? child}) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: SingleChildScrollView(
        // service: null is the login-mode contract; the page must support it
        // because the FfiChatService is not constructed before login.
        child: child ?? const BootstrapSettingsSection(service: null),
      ),
    ),
  );
}

Future<void> _pumpSettled(WidgetTester tester, [Widget? root]) async {
  // Use a wide surface so all RadioListTiles fit on one row.
  await tester.binding.setSurfaceSize(const Size(1200, 1400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(root ?? _harness());
  // Drain initState's async Prefs reads.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BootstrapSettingsSection - desktop mode row', () {
    testWidgets('default mode is auto and all three radios are present', (
      tester,
    ) async {
      await _initPrefs();
      await _pumpSettled(tester);

      // Three RadioListTiles: manual / auto / lan.
      expect(find.byType(RadioListTile<String>), findsNWidgets(3));
      expect(find.byKey(UiKeys.settingsBootstrapModeManual), findsOneWidget);
      expect(find.byKey(UiKeys.settingsBootstrapModeAuto), findsOneWidget);
      expect(find.byKey(UiKeys.settingsBootstrapModeLan), findsOneWidget);

      // Auto is the default per Prefs.getBootstrapNodeMode().
      // Check by reading the groupValue from one of the tiles.
      final autoTile = tester.widget<RadioListTile<String>>(
        find.byWidgetPredicate(
          (w) => w is RadioListTile<String> && w.value == 'auto',
        ),
      );
      expect(
        autoTile.groupValue,
        'auto',
        reason: 'Auto is the documented default mode',
      );
    });

    testWidgets(
      'tapping manual radio persists mode to Prefs and shows manual input '
      'expand button',
      (tester) async {
        await _initPrefs();
        await _pumpSettled(tester);

        // Tap the "manual" radio.
        final manualRadio = find.byKey(UiKeys.settingsBootstrapModeManual);
        await tester.tap(manualRadio);
        // The on-change handler is async (writes to Prefs then reloads state).
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // Mode was persisted.
        final mode = await Prefs.getBootstrapNodeMode();
        expect(
          mode,
          'manual',
          reason: 'Tapping a mode radio must persist via Prefs',
        );

        // The "Manual node input" expand button appears in manual mode (only).
        expect(
          find.textContaining(RegExp('[Mm]anual')),
          findsWidgets,
          reason: 'Manual mode reveals the manual-input affordance',
        );
      },
    );

    testWidgets('seeded current node prefs surface as a current-node tile', (
      tester,
    ) async {
      // Pre-seed via the documented Prefs keys (set via the public setter so
      // the implementation is the contract, not the underlying key names).
      await _initPrefs();
      await Prefs.setCurrentBootstrapNode(
        'bootstrap.example.com',
        33445,
        'A' * 64,
      );
      await _pumpSettled(tester);

      expect(
        find.textContaining('bootstrap.example.com:33445'),
        findsOneWidget,
        reason: 'Current node card surfaces the host:port pair',
      );
    });

    testWidgets('manual-mode expand toggle flips the manual input row', (
      tester,
    ) async {
      await _initPrefs();
      // Start directly in manual mode so the "Manual node input" button is
      // visible immediately. Bypassing the radio tap removes one source of
      // flake in this assertion.
      await Prefs.setBootstrapNodeMode('manual');
      await _pumpSettled(tester);

      // The expand button is an OutlinedButton.icon with an expand_more icon.
      expect(
        find.byIcon(Icons.expand_more),
        findsOneWidget,
        reason: 'Manual mode shows a closed expand-more chevron initially',
      );
      expect(
        find.byKey(UiKeys.manualNodeInputButton),
        findsOneWidget,
        reason: 'Manual mode ships a stable anchor for the expand affordance',
      );
      expect(find.byKey(UiKeys.manualNodeHostField), findsNothing);
      expect(find.byKey(UiKeys.manualNodePortField), findsNothing);
      expect(find.byKey(UiKeys.manualNodePubkeyField), findsNothing);
      expect(find.byKey(UiKeys.manualNodeTestButton), findsNothing);

      // Tap to expand.
      await tester.tap(find.byKey(UiKeys.manualNodeInputButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byIcon(Icons.expand_less),
        findsOneWidget,
        reason: 'After expand, the chevron flips to expand_less',
      );
      expect(
        find.byKey(UiKeys.manualNodeHostField),
        findsOneWidget,
        reason: 'Expanded manual mode exposes a stable host-field anchor',
      );
      expect(find.byKey(UiKeys.manualNodePortField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodePubkeyField), findsOneWidget);
      expect(find.byKey(UiKeys.manualNodeTestButton), findsOneWidget);
    });
  });
}
