// Real-UI L1 gate for the RegisterPage PASSWORD-STRENGTH BAR + password
// visibility toggle.
//
// Scope (all HERMETIC — no native lib): drives REAL typing into the mounted
// password field and asserts the REAL strength bar ramps 0 → 4 filled
// segments as the password strengthens, then asserts the visibility toggle
// flips `obscureText` on the live EditableText.
//
// Strength model (register_page.dart `_passwordStrength`):
//   ""             -> 0   (empty)
//   < 6 chars      -> 1
//   >= 6 chars     -> 2   (base)
//   >= 8 && (UPPER || digit)                 -> 3
//   >= 8 && UPPER && digit && special[!@#$%^&*] -> 4
//
// How a "filled" segment is detected (theme-independent): each segment is an
// AnimatedContainer keyed `register_strength_segment_<i>`. A filled segment's
// BoxDecoration.color is one of the OPAQUE ramp colours (alpha == 1.0); an
// empty segment is `outline.withValues(alpha: 0.2)` (alpha ~= 0.2). So we
// count segments whose colour alpha is ~1.0 — no dependency on the exact
// ColorScheme.
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
      throw Exception('stub: registration not exercised in strength test');
    },
    bootSession: (_) async {},
    teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
    showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
    navigateToHome: (context, service) async {},
  );
}

/// Counts password-strength segments rendered as "filled" by reading each
/// keyed AnimatedContainer's BoxDecoration colour alpha. Filled ramp colours
/// are opaque (alpha 1.0); the empty placeholder is alpha ~0.2.
int _filledSegments(WidgetTester tester) {
  var filled = 0;
  for (var i = 0; i < 4; i++) {
    final container = tester.widget<AnimatedContainer>(
      find.byKey(Key('register_strength_segment_$i')),
    );
    final decoration = container.decoration as BoxDecoration;
    final color = decoration.color!;
    // Opaque ramp colour => filled. Translucent outline => empty.
    if (color.a > 0.9) filled++;
  }
  return filled;
}

/// Reads `obscureText` from the password field's live EditableText.
bool _passwordObscured(WidgetTester tester) {
  final editable = tester.widget<EditableText>(
    find.descendant(
      of: find.byKey(UiKeys.registerPagePasswordField),
      matching: find.byType(EditableText),
    ),
  );
  return editable.obscureText;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  late String passwordVisibility;

  setUpAll(() {
    passwordVisibility = lookupAppLocalizations(const Locale('en')).passwordVisibility;
  });

  setUp(() {
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  testWidgets('password-strength bar ramps 0 -> 1 -> 2 -> 3 -> 4 as the password strengthens',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    // The strength bar is present even with an empty password.
    expect(find.byKey(const Key('register_password_strength_bar')), findsOneWidget,
        reason: 'The password-strength bar must render in the RegisterPage.');

    // 0: empty password -> all 4 segments empty.
    expect(_filledSegments(tester), 0,
        reason: 'An empty password must show 0 filled strength segments.');

    // 1: < 6 chars.
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'abc');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300)); // let AnimatedContainer settle
    expect(_filledSegments(tester), 1,
        reason: 'A < 6 char password must fill exactly 1 strength segment.');

    // 2: >= 6 chars, no upper/digit/special.
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'abcdef');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_filledSegments(tester), 2,
        reason: 'A 6+ char lowercase password must fill exactly 2 segments.');

    // 3: >= 8 chars with an uppercase letter (no digit/special).
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'Abcdefgh');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_filledSegments(tester), 3,
        reason: 'An 8+ char password with an uppercase letter must fill 3 segments.');

    // 4: >= 8 chars with uppercase + digit + special.
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'Abcdef1!');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(_filledSegments(tester), 4,
        reason: 'An 8+ char password with upper+digit+special must fill all 4 segments.');
  });

  testWidgets('weak vs strong password produce visibly different filled-segment counts',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'ab');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final weak = _filledSegments(tester);

    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'Strong1!pass');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    final strong = _filledSegments(tester);

    expect(strong, greaterThan(weak),
        reason: 'A strong password must fill more segments than a weak one ($strong > $weak).');
    expect(weak, 1);
    expect(strong, 4);
  });

  testWidgets('password visibility toggle flips obscureText on the live field',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_wrap(_page()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'secret123');
    await tester.pump();

    // Default: obscured, icon shows visibility_off (i.e. "tap to reveal").
    expect(_passwordObscured(tester), isTrue,
        reason: 'The password field starts obscured.');
    expect(
      find.descendant(
        of: find.byKey(const Key('register_password_visibility_toggle')),
        matching: find.byIcon(Icons.visibility_off),
      ),
      findsOneWidget,
      reason: 'Obscured state shows the visibility_off icon.',
    );

    // Tap the keyed toggle -> reveal.
    await tester.tap(find.byKey(const Key('register_password_visibility_toggle')));
    await tester.pump();

    expect(_passwordObscured(tester), isFalse,
        reason: 'Tapping the visibility toggle must reveal the password (obscureText=false).');
    expect(
      find.descendant(
        of: find.byKey(const Key('register_password_visibility_toggle')),
        matching: find.byIcon(Icons.visibility),
      ),
      findsOneWidget,
      reason: 'Revealed state shows the visibility icon.',
    );

    // Tap again -> obscure again (idempotent round-trip).
    await tester.tap(find.byKey(const Key('register_password_visibility_toggle')));
    await tester.pump();
    expect(_passwordObscured(tester), isTrue,
        reason: 'A second tap must re-obscure the password.');

    // The toggle carries the passwordVisibility tooltip (label sanity).
    expect(
      tester.widget<IconButton>(find.byKey(const Key('register_password_visibility_toggle'))).tooltip,
      passwordVisibility,
      reason: 'The toggle must expose the passwordVisibility tooltip for a11y.',
    );
  });
}
