// L1 widget test locking the Add Friend dialog's two client-side guards
// (UI automation scenarios S55 + S56):
//
//   S55 — self-add guard (add_friend_dialog.dart:152-158): if the entered id
//         equals the self id (compareToxIds(rawId, accountKey), where
//         accountKey resolves through getSelfToxId()), the dialog shows the
//         `cannotAddSelf` SnackBar ('You cannot add yourself as a friend'),
//         does NOT pop, and NEVER calls service.addFriend.
//
//   S56 — duplicate-friend guard (add_friend_dialog.dart:188-194): if
//         getFriendList() already contains a friend whose normalized userId
//         matches the entered id (normalizeToxId(f.userId) == normalizedRaw),
//         the dialog shows the `alreadyFriend` SnackBar ('This user is already
//         in your friend list'), does NOT pop, and NEVER calls addFriend.
//
// Comparison casing (verified against lib/util/tox_utils.dart): both
// compareToxIds and the duplicate check normalize via normalizeToxId, which
// trims and (for 76-char input) takes the first 64 chars but does NOT
// lower-case. The comparison is therefore case-SENSITIVE. The fixtures here
// use a single repeated hex char per id, so the entered id, the stub's
// self id, and the stub's friend-list userId all match in case by construction.
//
// Widget test over a stub service: `_StubFfiChatService extends FfiChatService`
// overrides only the surface the guards read (getSelfToxId, getFriendList,
// isConnected, connectionStatusStream, addFriend). addFriend records whether it
// was ever invoked so each test can assert the guard short-circuits BEFORE any
// FFI dispatch. NOTE: constructing the FfiChatService superclass (`: super()`)
// opens the tim2tox FFI dylib (Tim2ToxFfi.open) and MessageHistoryPersistence,
// so this test DOES load the native lib — same as
// test/ui/add_friend_dialog_smoke_test.dart, which also runs without a
// skip-guard. It is not a pure-Dart, no-native test. Mirrors the sibling
// harness test/ui/add_friend_async_failure_test.dart.
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

// Exactly 76 hex chars each — the dialog validator is `^[0-9a-fA-F]{76}$`, so
// the length must be exact or _submit bails at validation before the guards
// run. Distinct repeated chars keep self id, entered id, and friend id from
// colliding except where a test intends them to.
final String _selfId = 'B' * 76; // the stub's getSelfToxId() value
final String _dupId = 'C' * 76; // entered id == an existing friend's id (S56)

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService({required this.friends}) : super();

  /// Friend list the duplicate guard reads. Set per test.
  final List<({String userId, String nickName, String status, bool online})>
      friends;

  /// True once addFriend is dispatched. Both guards must short-circuit before
  /// this, so every test asserts it stays false.
  bool addFriendCalled = false;

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  // The self-add guard compares the entered id against `accountKey`, the
  // extension getter that resolves through getSelfToxId().
  @override
  String? getSelfToxId() => _selfId;

  @override
  Future<List<({String userId, String nickName, String status, bool online})>>
      getFriendList() async => friends;

  @override
  Future<AddFriendResult> addFriend(String serverId,
      {String? requestMessage}) async {
    addFriendCalled = true;
    return const AddFriendResult(
      resultCode: 0,
      userId: '',
      resultInfo: '',
      dispatched: true,
    );
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
  // The guards don't fire HapticFeedback, but the dialog touches
  // SystemChannels.platform elsewhere; mock it (JSONMethodCodec) to be safe.
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

  group('AddFriendDialog self-add guard (S55)', () {
    testWidgets(
        'entering own Tox ID shows cannotAddSelf, keeps dialog open, never calls addFriend',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Empty friend list so the only guard that can fire is the self-add one.
      final service = _StubFfiChatService(friends: const []);
      addTearDown(service.disposeStub);
      String? snack;

      await tester.pumpWidget(_harness(service, (m) => snack = m));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Enter the SAME id getSelfToxId() returns → self-add guard must fire.
      await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _selfId);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
      await tester.pumpAndSettle();

      expect(snack, 'You cannot add yourself as a friend',
          reason:
              'self-add must surface the cannotAddSelf SnackBar (fallback text)');
      expect(find.byKey(UiKeys.addFriendSubmitButton), findsOneWidget,
          reason: 'dialog must stay mounted when self-add is rejected');
      expect(service.addFriendCalled, isFalse,
          reason:
              'self-add guard must short-circuit before any addFriend dispatch');
    });
  });

  group('AddFriendDialog duplicate-friend guard (S56)', () {
    testWidgets(
        'entering an existing friend shows alreadyFriend, keeps dialog open, never calls addFriend',
        (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Friend list contains a friend whose userId == the entered id (_dupId,
      // distinct from _selfId so the self-add guard does NOT fire first). The
      // duplicate check is normalizeToxId(f.userId) == normalizeToxId(entered);
      // identical strings match in any case, so this is the exact-match case.
      final service = _StubFfiChatService(friends: [
        (userId: _dupId, nickName: 'Dup', status: '', online: true),
      ]);
      addTearDown(service.disposeStub);
      String? snack;

      await tester.pumpWidget(_harness(service, (m) => snack = m));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _dupId);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
      await tester.pumpAndSettle();

      expect(snack, 'This user is already in your friend list',
          reason:
              'a duplicate add must surface the alreadyFriend SnackBar (fallback text)');
      expect(find.byKey(UiKeys.addFriendSubmitButton), findsOneWidget,
          reason: 'dialog must stay mounted when a duplicate add is rejected');
      expect(service.addFriendCalled, isFalse,
          reason:
              'duplicate guard must short-circuit before any addFriend dispatch');
    });
  });
}
