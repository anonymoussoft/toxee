import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/register_page.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// L1 widget test locking the RegisterPage *form validation* behaviour.
//
// Scope: the pure-form validation gate only — password/confirm mismatch,
// empty-nickname, over-length nickname/status, and the register-button
// enable/disable wiring. These run entirely inside
// `_formKey.currentState.validate()` and the button's `onPressed` guard,
// which fire *before* any FFI register call. We never drive a successful
// registration (that would call `AccountService.registerNewAccount`), so
// this test needs no native library — unlike
// `test/ui/register/register_page_widget_test.dart`, which is FFI-gated and
// covers the post-validation boot/navigation path.

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

/// Builds a [RegisterPage] whose register callback only *records* invocations
/// instead of running the real FFI flow. Any tap that gets past validation
/// would increment [registerCalls]; an invalid form never calls it. The other
/// session hooks are no-ops so that, even if a valid submit slips through, no
/// FFI/boot/navigation work is attempted.
RegisterPage _pageRecordingRegister(List<String> registerCalls) {
  return RegisterPage(
    registerAccount: ({
      required nickname,
      required statusMessage,
      required password,
    }) async {
      registerCalls.add(nickname);
      // Throw so the page short-circuits into its catch block instead of
      // proceeding to boot/navigate — keeps the test off the FFI path even
      // when validation passes.
      throw Exception('stub: registration not exercised in form test');
    },
    bootSession: (_) async {},
    teardownSession: ({required FfiChatService service, bool reEncryptProfile = true}) async {},
    showFirstRunBackupWizard: ({required context, required toxId, required nickname}) async {},
    navigateToHome: (context, service) async {},
  );
}

Finder _errorText(String message) =>
    find.descendant(of: find.byType(TextFormField), matching: find.text(message));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late String passwordsDoNotMatch;
  late String nicknameCannotBeEmpty;
  late String nicknameTooLong;
  late String statusMessageTooLong;
  late String statusMessageLabel;

  setUpAll(() {
    final l10n = lookupAppLocalizations(const Locale('en'));
    passwordsDoNotMatch = l10n.passwordsDoNotMatch;
    nicknameCannotBeEmpty = l10n.nicknameCannotBeEmpty;
    nicknameTooLong = l10n.nicknameTooLong;
    statusMessageTooLong = l10n.statusMessageTooLong;
    statusMessageLabel = l10n.statusMessage;
  });

  testWidgets(
      'mismatched password and confirm-password surfaces passwordsDoNotMatch on submit',
      (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'secret123');
    await tester.enterText(
        find.byKey(UiKeys.registerPageConfirmPasswordField), 'different');
    await tester.pump();

    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump();

    expect(_errorText(passwordsDoNotMatch), findsOneWidget,
        reason:
            'A confirm-password that differs from the password must fail validation with the mismatch error.');
    expect(registerCalls, isEmpty,
        reason:
            'Validation must gate the register call: a mismatched form must never reach registerAccount.');
  });

  testWidgets(
      'matching password and confirm-password clears the mismatch error and passes the validation gate',
      (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'secret123');
    await tester.enterText(
        find.byKey(UiKeys.registerPageConfirmPasswordField), 'wrong');
    await tester.pump();
    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump();
    expect(_errorText(passwordsDoNotMatch), findsOneWidget,
        reason: 'Sanity: the mismatch error is showing before we fix it.');

    // Fix the confirmation to match, then re-submit.
    await tester.enterText(
        find.byKey(UiKeys.registerPageConfirmPasswordField), 'secret123');
    await tester.pump();
    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump();

    expect(_errorText(passwordsDoNotMatch), findsNothing,
        reason: 'Matching passwords must clear the mismatch validation error.');
    expect(registerCalls, equals(<String>['Alice']),
        reason:
            'A fully valid form must pass the validation gate and reach registerAccount exactly once.');
  });

  testWidgets('empty nickname surfaces nicknameCannotBeEmpty and blocks registration',
      (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    // Leave nickname empty; matching passwords so only the nickname rule fails.
    await tester.enterText(find.byKey(UiKeys.registerPagePasswordField), 'secret123');
    await tester.enterText(
        find.byKey(UiKeys.registerPageConfirmPasswordField), 'secret123');
    await tester.pump();

    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton));
    await tester.pump();

    expect(_errorText(nicknameCannotBeEmpty), findsOneWidget,
        reason: 'An empty nickname must fail validation with the required error.');
    expect(registerCalls, isEmpty,
        reason: 'An empty nickname must gate the register call.');
  });

  testWidgets('over-length nickname disables the register button (length-guard gate)',
      (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    // `calculateTextLength` weights CJK as 1.0 and ASCII as 0.5; the guard
    // trips at > 12 width units. 13 CJK chars = 13.0 > 12 (and stays under the
    // field's maxLength of 24). ASCII alone can't exceed it because maxLength
    // caps the field at 24 chars = 12.0 width units.
    await tester.enterText(
        find.byKey(UiKeys.registerPageNicknameField), '中' * 13);
    await tester.pump();

    final button =
        tester.widget<FilledButton>(find.byKey(UiKeys.registerPageRegisterButton));
    expect(button.onPressed, isNull,
        reason:
            'An over-length nickname must disable the register button via the onPressed guard.');

    // The nickname field's over-length error text must also be rendered, so a
    // regression that kept the button disabled but dropped the field error is
    // caught. The decoration's reactive `errorText` shows whenever
    // calculateTextLength > 12, so no explicit validate() trigger is needed.
    expect(_errorText(nicknameTooLong), findsOneWidget,
        reason: 'The nickname field must show its over-length error text.');

    // Tapping a disabled button is a no-op; registration must not run.
    await tester.tap(find.byKey(UiKeys.registerPageRegisterButton),
        warnIfMissed: false);
    await tester.pump();
    expect(registerCalls, isEmpty,
        reason: 'A disabled register button must not trigger registration.');
  });

  testWidgets('valid nickname keeps the register button enabled', (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    await tester.pump();

    final button =
        tester.widget<FilledButton>(find.byKey(UiKeys.registerPageRegisterButton));
    expect(button.onPressed, isNotNull,
        reason: 'A within-limit nickname must leave the register button enabled.');
  });

  testWidgets('over-length status message disables the register button',
      (tester) async {
    final registerCalls = <String>[];
    await tester.pumpWidget(_wrap(_pageRecordingRegister(registerCalls)));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.registerPageNicknameField), 'Alice');
    // Status guard trips at > 24 width units. 25 CJK chars = 25.0 > 24 (under
    // the field's maxLength of 48); ASCII can't reach it (maxLength caps at
    // 48 chars = 24.0 width units, which is not > 24).
    //
    // Locate the status field by its decoration label rather than positional
    // `.at(1)` so the test survives field reordering. The status TextFormField
    // (register_page.dart:~340) is the only field carrying the `statusMessage`
    // label/hint text; anchor on that label Text and walk up to its enclosing
    // TextFormField. (It carries the string as both labelText and hintText, so
    // we take `.first` and resolve the single ancestor field.)
    final statusField = find.ancestor(
      of: find.text(statusMessageLabel).first,
      matching: find.byType(TextFormField),
    );
    expect(statusField, findsOneWidget,
        reason: 'The status field must be uniquely locatable by its label.');
    await tester.enterText(statusField, '中' * 25);
    await tester.pump();

    final button =
        tester.widget<FilledButton>(find.byKey(UiKeys.registerPageRegisterButton));
    expect(button.onPressed, isNull,
        reason:
            'An over-length status message must disable the register button, surfacing $statusMessageTooLong as a field error.');
    // The status field's over-length error text is also rendered.
    expect(_errorText(statusMessageTooLong), findsOneWidget,
        reason: 'The status field must show its over-length error text.');
  });
}
