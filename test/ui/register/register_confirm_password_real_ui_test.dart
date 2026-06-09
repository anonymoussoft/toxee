// Real-UI L1 gate for the RegisterPage CONFIRM-PASSWORD match/mismatch
// indicator + the confirm-password visibility toggle.
//
// Scope (all HERMETIC — no native lib): drives REAL typing and asserts the
// REAL suffix indicator:
//   * confirm != password (both non-empty) -> red `Icons.cancel`,
//   * confirm == password                  -> green `Icons.check_circle`,
//   * the indicator is absent until BOTH fields have text,
//   * the confirm visibility toggle flips `obscureText` on the live field.
//
// The indicator is keyed `register_confirm_match_icon`; the production widget
// swaps `Icons.check_circle`/`Icons.cancel` and primary/error colour based on
// `_confirmPasswordController.text == _passwordController.text`. We read the
// live `Icon` widget rather than re-deriving the rule.
//
// Mobile parity: register_page.dart is shared Dart, so this gate covers iOS /
// Android / desktop identically.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: child,
  );
}

RegisterPage _page() {
  return RegisterPage(
    registerAccount: ({
      required nickname,
      required statusMessage,
      required password,
    }) async {
      throw Exception('stub: registration not exercised in confirm test');
    },
    bootSession: (_) async {},
    teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
    showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
    navigateToHome: (context, service) async {},
  );
}

Icon _matchIcon(WidgetTester tester) =>
    tester.widget<Icon>(find.byKey(const Key('register_confirm_match_icon')));

bool _confirmObscured(WidgetTester tester) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(UiKeys.registerPageConfirmPasswordField),
      matching: find.byType(EditableText),
    ),
  );
  return editable.obscureText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  testWidgets('match indicator is hidden until both password and confirm have text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    // No text anywhere -> no indicator.
    expect(find.byKey(const Key('register_confirm_match_icon')), findsNothing,
        reason: 'The match indicator must be absent before any input.');

    // Only the confirm field typed (password still empty) -> still no indicator,
    // because the widget gates on BOTH controllers being non-empty.
    await tester.enterText(find.byKey(UiKeys.registerPageConfirmPasswordField), 'abc');
    await tester.pump();
    expect(find.byKey(const Key('register_confirm_match_icon')), findsNothing,
        reason: 'The indicator must stay hidden while the password field is empty.');
  });

  testWidgets('mismatch shows the red cancel icon; matching shows the green check icon',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    final cs = Theme.of(tester.element(find.byType(RegisterPage))).colorScheme;

    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'secret123');
    await tester.enterText(find.byKey(UiKeys.registerPageConfirmPasswordField), 'different');
    await tester.pump();

    // MISMATCH -> Icons.cancel, error colour.
    expect(find.byKey(const Key('register_confirm_match_icon')), findsOneWidget,
        reason: 'With both fields filled, the match indicator must render.');
    var icon = _matchIcon(tester);
    expect(icon.icon, Icons.cancel,
        reason: 'A mismatching confirm-password must show Icons.cancel.');
    expect(icon.color, cs.error,
        reason: 'The mismatch icon must use the error colour.');

    // Fix the confirm to MATCH -> Icons.check_circle, primary colour.
    await tester.enterText(find.byKey(UiKeys.registerPageConfirmPasswordField), 'secret123');
    await tester.pump();
    icon = _matchIcon(tester);
    expect(icon.icon, Icons.check_circle,
        reason: 'A matching confirm-password must show Icons.check_circle.');
    expect(icon.color, cs.primary,
        reason: 'The match icon must use the primary colour.');
  });

  testWidgets('confirm visibility toggle flips obscureText on the live confirm field',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageConfirmPasswordField), 'secret123');
    await tester.pump();

    expect(_confirmObscured(tester), isTrue,
        reason: 'The confirm field starts obscured.');

    await tester.tap(find.byKey(const Key('register_confirm_visibility_toggle')));
    await tester.pump();
    expect(_confirmObscured(tester), isFalse,
        reason: 'Tapping the confirm visibility toggle must reveal the field.');

    await tester.tap(find.byKey(const Key('register_confirm_visibility_toggle')));
    await tester.pump();
    expect(_confirmObscured(tester), isTrue,
        reason: 'A second tap must re-obscure the confirm field.');
  });
}
