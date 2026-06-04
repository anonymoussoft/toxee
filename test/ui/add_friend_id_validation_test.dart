// L1 widget test for the Add Friend dialog's Tox-ID FORMAT validation,
// submit-gating, and the paste / cancel controls (roadmap L1-C "wrong-format
// Tox ID").
//
// New angle (does NOT overlap the sibling AddFriend tests):
//   - add_friend_dialog_smoke_test.dart    — submit disabled until id+message
//   - add_friend_async_failure_test.dart   — failure-result SnackBar + no-pop
//   - add_friend_offline_queue_test.dart   — offline banner + queued snack
//   - add_friend_guards_test.dart          — self-add + duplicate guards
//
// Here we exercise the FORMAT validator `_kToxAddressRegex = ^[0-9a-fA-F]{76}$`
// (add_friend_dialog.dart `_validateToxId`, ~lines 247-256). Critically, the
// submit button enables as soon as id+message are non-empty, so a wrong-format
// id still ENABLES submit — the format check only runs on submit-time via
// `_formKey.currentState.validate()`. On a format failure the validator's
// errorText surfaces under the TextFormField, the dialog does NOT pop, and
// `addFriend` is NEVER dispatched. A valid 76-hex id passes and dispatches.
//
// Widget test over a stub service: `_StubFfiChatService extends FfiChatService`
// records whether addFriend was dispatched and returns a configured
// AddFriendResult. NOTE: constructing the FfiChatService superclass (`: super()`)
// opens the tim2tox FFI dylib (Tim2ToxFfi.open) and MessageHistoryPersistence,
// so this test DOES load the native lib — same as
// test/ui/add_friend_dialog_smoke_test.dart, which also runs without a
// skip-guard. It is not a pure-Dart, no-native test. The dialog's onShowSnackBar
// hook captures snackbar text without a real ScaffoldMessenger lookup.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/add_friend_dialog.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

// Exactly 76 hex chars — the validator is `^[0-9a-fA-F]{76}$`, so this is the
// only shape that passes the format gate.
final String _validToxId = 'A' * 76;

// Wrong-format candidates. Each is non-empty (so submit ENABLES) but fails the
// 76-hex regex for a distinct reason.
final String _tooShortId = 'A' * 64; // valid hex, wrong length (bare pubkey)
final String _tooLongId = 'A' * 77; // valid hex, one char too long
final String _nonHexId = 'Z' * 76; // correct length, non-hex characters

// The English error surfaced by the format validator (addFriendInvalidToxIdHint).
const String _invalidFormatError =
    'Tox address must be 76 hexadecimal characters';

// The success SnackBar text on the online requestSent branch
// (add_friend_dialog.dart:138-139,224). The stub reports isConnected == true,
// so _submit surfaces successText, not the offline queuedText. successText
// resolves to TencentCloudChatLocalizations.requestSent, whose English value is
// 'Request Sent'.
const String _requestSentText = 'Request Sent';

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();

  /// Recorded: set true the moment addFriend is dispatched.
  bool addFriendCalled = false;

  /// The id passed to addFriend (for assertions), null until dispatched.
  String? addFriendArg;

  /// Result the (success-path) addFriend call returns.
  AddFriendResult addFriendResult = AddFriendResult(
    resultCode: 0,
    userId: 'A' * 76,
    resultInfo: '',
    dispatched: true,
  );

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  // Self-add guard compares against `accountKey` (resolves via getSelfToxId).
  // A distinct 76-char id (≠ _validToxId) keeps the guard from firing.
  @override
  String? getSelfToxId() => 'B' * 76;

  // Empty friend list so the duplicate-friend guard passes.
  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async => [];

  @override
  Future<AddFriendResult> addFriend(String serverId,
      {String? requestMessage}) async {
    addFriendCalled = true;
    addFriendArg = serverId;
    return addFriendResult;
  }

  void disposeStub() => unawaited(_connection.close());
}

Widget _harness(_StubFfiChatService service, void Function(String) onSnack) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(
      body: Builder(
        builder: (ctx) => Center(
          child: TextButton(
            onPressed: () => showDialog<void>(
              context: ctx,
              builder: (_) => Dialog(
                child: AddFriendDialog(
                  service: service,
                  onShowSnackBar: onSnack,
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;
  // HapticFeedback / clipboard go through SystemChannels.platform
  // (JSONMethodCodec). The mock channel must match that codec or calls throw.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  // Clipboard payload returned by the mock for Clipboard.getData. Mutable so
  // the paste test can stage a value before tapping the paste button.
  String? clipboardText;

  setUp(() {
    clipboardText = null;
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(platformChannel,
        (MethodCall call) async {
      if (call.method == 'Clipboard.getData') {
        // Clipboard.getData expects a map shaped like {'text': <value>}.
        return <String, dynamic>{'text': clipboardText};
      }
      // Swallow HapticFeedback / SystemChrome / etc.
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  // Opens the dialog and types the given id; the message field auto-fills with
  // the default request message in didChangeDependencies, so submit enables.
  Future<void> openAndEnter(WidgetTester tester, _StubFfiChatService service,
      void Function(String) onSnack, String id) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(service, onSnack));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.addFriendIdInput), id);
    await tester.pumpAndSettle();
  }

  group('wrong-format Tox ID is rejected at submit-time', () {
    for (final entry in <(String, String, String)>[
      (_tooShortId, '64-char (bare pubkey, too short)', 'A*64'),
      (_tooLongId, '77-char (one char too long)', 'A*77'),
      (_nonHexId, '76 non-hex chars', 'Z*76'),
    ]) {
      final id = entry.$1;
      final label = entry.$2;

      testWidgets('$label surfaces the format error and does not dispatch',
          (WidgetTester tester) async {
        final service = _StubFfiChatService();
        addTearDown(service.disposeStub);
        String? snack;

        await openAndEnter(tester, service, (m) => snack = m, id);

        // Submit ENABLES on non-empty id+message even though the format is
        // wrong — that's the smoke-test contract. The format check is deferred
        // to submit.
        expect(
          tester
              .widget<FilledButton>(find.byKey(UiKeys.addFriendSubmitButton))
              .onPressed,
          isNotNull,
          reason:
              'submit must enable on non-empty id+message before format validation',
        );

        await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
        await tester.pumpAndSettle();

        // The validator's errorText is rendered under the field.
        expect(find.text(_invalidFormatError), findsOneWidget,
            reason:
                'a wrong-format Tox ID must surface the validator errorText on submit');
        // Dialog stayed mounted (no pop).
        expect(find.byKey(UiKeys.addFriendSubmitButton), findsOneWidget,
            reason: 'the dialog must NOT pop when the Tox ID is malformed');
        // addFriend never dispatched.
        expect(service.addFriendCalled, isFalse,
            reason:
                'addFriend must NOT be dispatched when format validation fails');
        // No SnackBar (validation short-circuits before the snackbar paths).
        expect(snack, isNull,
            reason:
                'a format-validation failure surfaces inline errorText, not a SnackBar');
      });
    }
  });

  testWidgets('valid 76-hex Tox ID passes validation and dispatches addFriend',
      (WidgetTester tester) async {
    final service = _StubFfiChatService();
    addTearDown(service.disposeStub);
    String? snack;

    await openAndEnter(tester, service, (m) => snack = m, _validToxId);

    await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
    await tester.pumpAndSettle();

    expect(find.text(_invalidFormatError), findsNothing,
        reason: 'a valid 76-hex id must not surface the format error');
    expect(service.addFriendCalled, isTrue,
        reason: 'a valid Tox ID must dispatch addFriend');
    expect(service.addFriendArg, _validToxId,
        reason: 'addFriend must receive the entered Tox ID');
    expect(snack, _requestSentText,
        reason: 'an online success must surface the requestSent text '
            "('Request Sent'), not the offline queued text");
    // A successful add pops the dialog.
    expect(find.byKey(UiKeys.addFriendSubmitButton), findsNothing,
        reason: 'a successful add must pop the dialog');
  });

  testWidgets('Cancel button pops the dialog without dispatching addFriend',
      (WidgetTester tester) async {
    final service = _StubFfiChatService();
    addTearDown(service.disposeStub);
    String? snack;

    // Even with a valid id staged, Cancel must not dispatch.
    await openAndEnter(tester, service, (m) => snack = m, _validToxId);

    await tester.tap(find.byKey(UiKeys.addFriendCancelButton));
    await tester.pumpAndSettle();

    expect(find.byKey(UiKeys.addFriendSubmitButton), findsNothing,
        reason: 'Cancel must pop the dialog');
    expect(service.addFriendCalled, isFalse,
        reason: 'Cancel must NOT dispatch addFriend');
    expect(snack, isNull,
        reason: 'Cancel must not surface any SnackBar');
  });

  testWidgets('Paste button fills the Tox ID field from the clipboard',
      (WidgetTester tester) async {
    final service = _StubFfiChatService();
    addTearDown(service.disposeStub);

    // Stage a clipboard value (with surrounding whitespace the dialog trims).
    clipboardText = '  $_validToxId  ';

    await openAndEnter(tester, service, (_) {}, '');

    await tester.tap(find.byKey(UiKeys.addFriendPasteButton));
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<TextFormField>(find.byKey(UiKeys.addFriendIdInput))
          .controller
          ?.text,
      _validToxId,
      reason: 'Paste must populate the Tox ID field with the trimmed clipboard text',
    );
    expect(service.addFriendCalled, isFalse,
        reason: 'Paste must not dispatch addFriend on its own');
  });
}
