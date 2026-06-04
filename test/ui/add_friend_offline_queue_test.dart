// Regression test for roadmap item 7 / L1-B: "Add Friend offline queue + banner".
//
// The offline UX in add_friend_dialog.dart has two distinct, observable parts:
//
//   1. Offline banner (add_friend_dialog.dart:378-388): when
//      `!service.isConnected`, the dialog renders an `_OfflineBanner` warning
//      that the request will be queued. The banner is wired to the live
//      `connectionStatusStream` (initState:95-99) so it appears/disappears as
//      connectivity changes while the dialog is open.
//
//   2. Queued SnackBar (add_friend_dialog.dart:220-224): on a *successful*
//      dispatch while offline, `_submit` shows the locale "requestQueued" text
//      ("Offline — request queued ...") instead of the online "requestSent"
//      text, then pops. Tox queues the outgoing request and delivers it on
//      reconnect, so offline submit is NOT silently dropped.
//
// Widget test over a stub service: `_StubFfiChatService extends FfiChatService`
// drives `isConnected` and the connection stream. NOTE: constructing the
// FfiChatService superclass (`: super()`) opens the tim2tox FFI dylib
// (Tim2ToxFfi.open) and MessageHistoryPersistence, so this test DOES load the
// native lib — same as test/ui/add_friend_dialog_smoke_test.dart, which also
// runs without a skip-guard. It is not a pure-Dart, no-native test; the stub
// only overrides the surface the dialog reads. `onShowSnackBar` captures the
// feedback text without a real ScaffoldMessenger.
//
// Note: `_localeText` has no switch case for 'offlineBanner' / 'requestQueued',
// so the dialog renders the hardcoded English fallback strings defined inline
// in the dialog. We assert against those fallbacks (the actual rendered text).
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

// The hardcoded fallback strings the dialog renders for the offline UX
// (`_localeText` has no switch case for these keys, so it returns the fallback).
const String _bannerText =
    'Offline — your friend request will be queued and sent automatically when you reconnect.';
const String _queuedSnackText =
    'Offline — request queued and will be sent when you reconnect';

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService({required bool connected})
      : _connected = connected,
        super();

  bool _connected;
  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  /// The result the next addFriend call returns. Defaults to a successful
  /// dispatch (resultCode 0, dispatched true) — Tox accepts/queues the request
  /// regardless of connectivity, so even an offline submit "succeeds" at the
  /// dispatch layer and the queued SnackBar branch fires.
  AddFriendResult addFriendResult = AddFriendResult(
    resultCode: 0,
    userId: 'A' * 76,
    resultInfo: '',
    dispatched: true,
  );

  @override
  bool get isConnected => _connected;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  /// Drive a connectivity change to the live dialog (mirrors the real service
  /// emitting on the DHT connection coming up/down).
  void emitConnected(bool connected) {
    _connected = connected;
    _connection.add(connected);
  }

  // The dialog's self-add guard compares the entered id against `accountKey`,
  // an extension getter resolving through getSelfToxId(). Return a distinct
  // 76-char id (≠ _validToxId) so the guard passes without touching real FFI.
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
  // HapticFeedback.lightImpact() on the submit paths goes through
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

  Future<void> openDialog(WidgetTester tester, _StubFfiChatService service,
      void Function(String) onSnack) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_harness(service, onSnack));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  group('AddFriendDialog offline banner', () {
    testWidgets('renders the offline banner when service.isConnected is false',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: false);
      addTearDown(service.disposeStub);

      await openDialog(tester, service, (_) {});

      expect(find.text(_bannerText), findsOneWidget,
          reason:
              'offline dialog must warn the user the request will be queued');
      expect(find.byIcon(Icons.cloud_off), findsOneWidget,
          reason: 'offline banner shows a cloud_off icon');
    });

    testWidgets('does NOT render the offline banner when connected',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: true);
      addTearDown(service.disposeStub);

      await openDialog(tester, service, (_) {});

      expect(find.text(_bannerText), findsNothing,
          reason: 'no offline banner should appear while online');
      expect(find.byIcon(Icons.cloud_off), findsNothing,
          reason: 'no cloud_off icon while online');
    });

    testWidgets(
        'banner appears when connection drops while the dialog is open',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: true);
      addTearDown(service.disposeStub);

      await openDialog(tester, service, (_) {});
      expect(find.text(_bannerText), findsNothing,
          reason: 'starts online — no banner');

      // Connection drops while the dialog is mounted.
      service.emitConnected(false);
      await tester.pumpAndSettle();

      expect(find.text(_bannerText), findsOneWidget,
          reason: 'dialog listens to connectionStatusStream and shows the '
              'banner when the connection drops');
    });

    testWidgets(
        'banner disappears when connection is restored while dialog is open',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: false);
      addTearDown(service.disposeStub);

      await openDialog(tester, service, (_) {});
      expect(find.text(_bannerText), findsOneWidget,
          reason: 'starts offline — banner shown');

      service.emitConnected(true);
      await tester.pumpAndSettle();

      expect(find.text(_bannerText), findsNothing,
          reason: 'banner must clear once the connection is restored');
    });
  });

  group('AddFriendDialog offline submit', () {
    testWidgets(
        'offline submit surfaces the queued SnackBar (not silent), then pops',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: false);
      addTearDown(service.disposeStub);
      String? snack;

      await openDialog(tester, service, (m) => snack = m);

      await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _validToxId);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
      await tester.pumpAndSettle();

      expect(snack, _queuedSnackText,
          reason: 'an offline add must surface the queued message, '
              'differentiating it from the online "request sent" text');
      expect(find.byKey(UiKeys.addFriendSubmitButton), findsNothing,
          reason: 'a queued (dispatched) offline add still pops the dialog');
    });

    testWidgets('online submit surfaces the success SnackBar, not the queued one',
        (WidgetTester tester) async {
      final service = _StubFfiChatService(connected: true);
      addTearDown(service.disposeStub);
      String? snack;

      await openDialog(tester, service, (m) => snack = m);

      await tester.enterText(find.byKey(UiKeys.addFriendIdInput), _validToxId);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(UiKeys.addFriendSubmitButton));
      await tester.pumpAndSettle();

      expect(snack, isNot(_queuedSnackText),
          reason: 'online success must NOT show the offline-queued message');
      expect(snack, isNotNull,
          reason: 'online success still surfaces a SnackBar');
      expect(find.byKey(UiKeys.addFriendSubmitButton), findsNothing,
          reason: 'a successful add pops the dialog');
    });
  });
}
