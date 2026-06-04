// Regression test for finding F13 (roadmap L1-F13): AddFriend must surface a
// failed add to the user instead of silently logging success.
//
// The bug: addFriend could return a non-zero result_code (e.g. 6770 /
// ERR_INVALID_PARAMETERS, or an offline dispatch failure) while an OnSuccess
// log fired and the dialog popped with no feedback. The fix
// (add_friend_dialog.dart:207-229) branches on result.isSuccess: on failure it
// shows a SnackBar with the result detail and does NOT pop (input preserved);
// on success it pops + shows the success SnackBar.
//
// Pure L1 widget test: a stub FfiChatService returns a configurable
// AddFriendResult, so no native lib is touched. The dialog's onShowSnackBar
// hook captures the message text without a real ScaffoldMessenger lookup.
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

// Exactly 76 hex chars — the dialog validator is `^[0-9a-fA-F]{76}$`, so the
// length must be exact or _submit bails at validation before addFriend runs.
final String _validToxId = 'A' * 76;

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService(this.addFriendResult) : super();

  /// The result the next addFriend call returns. Set per test.
  AddFriendResult addFriendResult;
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  // The dialog's self-add guard compares the entered id against `accountKey`,
  // which is an extension getter resolving through getSelfToxId(). Return a
  // distinct 76-char id (≠ _validToxId) so the guard passes without touching
  // the real FFI (which is uninitialised in this stub).
  @override
  String? getSelfToxId() => 'B' * 76;

  // Empty friend list so the duplicate-friend guard passes.
  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async => [];

  @override
  Future<AddFriendResult> addFriend(String serverId,
          {String? requestMessage}) async =>
      addFriendResult;

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
  // HapticFeedback.lightImpact() on the failure path goes through
  // SystemChannels.platform (JSONMethodCodec) — mock it or the call throws.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  setUp(() {
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        platformChannel, (MethodCall call) async => null);
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  });

  testWidgets('failed add shows SnackBar, keeps dialog open, preserves input',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _StubFfiChatService(const AddFriendResult(
      resultCode: 6770,
      userId: '',
      resultInfo: 'Friend add requires full Tox address',
      dispatched: true, // dispatched but non-zero code => isSuccess == false
    ));
    addTearDown(service.disposeStub);
    String? snack;

    await tester.pumpWidget(_harness(service, (m) => snack = m));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _validToxId);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
    await tester.pumpAndSettle();

    // Dialog stayed open (did NOT pop).
    expect(find.byKey(UiKeys.addFriendSubmitButton), findsOneWidget,
        reason: 'dialog must stay mounted on a failed add');
    // SnackBar surfaced the failure detail.
    expect(snack, isNotNull,
        reason: 'a failed add must surface a SnackBar, not log silent success');
    expect(snack, contains('Friend add requires full Tox address'),
        reason: 'SnackBar must include result.resultInfo');
    // Input preserved (cleared only on success).
    expect(
      tester
          .widget<TextFormField>(find.byKey(UiKeys.addFriendIdInput))
          .controller
          ?.text,
      _validToxId,
      reason: 'the Tox ID input must be preserved after a failed add',
    );
  });

  testWidgets('successful add pops the dialog and shows a success SnackBar',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final service = _StubFfiChatService(AddFriendResult(
      resultCode: 0,
      userId: _validToxId,
      resultInfo: '',
      dispatched: true,
    ));
    addTearDown(service.disposeStub);
    String? snack;

    await tester.pumpWidget(_harness(service, (m) => snack = m));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _validToxId);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
    await tester.pumpAndSettle();

    // Dialog popped.
    expect(find.byKey(UiKeys.addFriendSubmitButton), findsNothing,
        reason: 'dialog must pop on a successful add');
    expect(snack, isNotNull, reason: 'success must still surface a SnackBar');
    expect(snack, isNot(contains('Friend add requires full Tox address')));
  });
}
