// Hermetic smoke for the "New conversation → Add Contact" entry path.
//
// Drives the smallest hermetic surface that still proves the new ValueKeys
// work end-to-end. We do NOT boot `EchoUIKitApp` or `HomePage` because those
// flows transit the hybrid startup chain described in `CLAUDE.md`
// (`AppBootstrap`, `SessionRuntimeCoordinator`, FakeUIKit, Tim2ToxSdkPlatform,
// binary-replacement hooks) and would either touch real FFI session init or
// require invasive production seams just for the smoke.
//
// Instead, this test mounts a plain `MaterialApp` whose body is the real
// `NewEntryButton`. Its `onAddFriend` callback opens the real
// `AddFriendDialog` with a minimal `FfiChatService` subclass. That keeps the
// test faithful to the user-visible interaction contract while staying
// hermetic:
//
//   1. Tap `UiKeys.newEntryMenuButton` to open the popup menu.
//   2. Tap `UiKeys.newEntryAddContactItem` to launch the real dialog.
//   3. Verify `UiKeys.addFriendIdInput` is present.
//   4. Verify `UiKeys.addFriendSubmitButton` is disabled before the user
//      enters a Tox ID, then becomes enabled after a valid ID is typed.
//
// Lives under `test/ui/` (was under `integration_test/` before 2026-05-28).
// `TestWidgetsFlutterBinding` + mock channels make this a widget test, not an
// integration test; `flutter test integration_test/` would force a needless
// host platform build on every CI run. Moving it here puts it on the cheap
// `flutter test` path that already runs in `.github/workflows/analyze.yml`.
//
// Plugin channels: this path does not require path_provider / secure_storage
// / audioplayers, but we still install a narrow no-op handler for
// `HapticFeedback` on `flutter/platform` so a future dialog-side success
// path tweak does not turn this smoke into a `MissingPluginException`.
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
import 'package:toxee/ui/home/home_widgets.dart';
import 'package:toxee/ui/testing/ui_keys.dart';

typedef _SmokeHarness = ({
  void Function() teardown,
});

class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();

  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connectionController.stream;

  void disposeStub() {
    unawaited(_connectionController.close());
  }
}

Future<_SmokeHarness> _installPluginStubs() async {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  // SystemChannels.platform uses JSONMethodCodec (not the default
  // StandardMethodCodec). The mock channel must match or the test framework
  // decodes our calls with the wrong codec and throws FormatException:
  // "Message corrupted" the moment MaterialApp's Title widget invokes
  // SystemChrome.setApplicationSwitcherDescription during pump.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async {
    // Swallow every platform call (HapticFeedback.vibrate,
    // SystemChrome.setApplicationSwitcherDescription, etc.) — none of them
    // matter for the assertions in this smoke.
    return null;
  });

  void teardown() {
    messenger.setMockMethodCallHandler(platformChannel, null);
  }

  return (teardown: teardown);
}

Widget _harness(
  _StubFfiChatService service,
  GlobalKey<NavigatorState> navigatorKey,
) {
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
      body: Center(
        child: NewEntryButton(
          onAddFriend: () async {
            await showDialog<void>(
              context: navigatorKey.currentContext!,
              builder: (dialogContext) => Dialog(
                child: AddFriendDialog(service: service),
              ),
            );
          },
          onCreateGroup: () async {},
        ),
      ),
    ),
    // navigatorKey is created fresh per test in setUp. A previous version
    // declared it as a top-level `final GlobalKey<NavigatorState>` so every
    // test reused the same instance — that works for a single testWidgets
    // (the framework detaches the key when the widget tree disposes) but
    // breaks the moment a second test is added: if there's any inter-test
    // residue or a pumpWidget swap within one test, two widgets briefly hold
    // the same GlobalKey and Flutter throws "Multiple widgets used the same
    // GlobalKey". Per-test creation is the Flutter-recommended pattern.
    navigatorKey: navigatorKey,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _SmokeHarness harness;
  late _StubFfiChatService service;
  late GlobalKey<NavigatorState> navigatorKey;

  setUp(() async {
    harness = await _installPluginStubs();
    service = _StubFfiChatService();
    navigatorKey = GlobalKey<NavigatorState>();
  });

  tearDown(() {
    harness.teardown();
    service.disposeStub();
  });

  testWidgets(
      'new entry add-contact flow exposes keyed dialog fields and disabled submit state',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(service, navigatorKey));
    await tester.pump();

    await tester.tap(find.byKey(UiKeys.newEntryMenuButton));
    await tester.pumpAndSettle();

    expect(find.byKey(UiKeys.newEntryAddContactItem), findsOneWidget,
        reason: 'the add-contact popup entry must be discoverable by key');

    await tester.tap(find.byKey(UiKeys.newEntryAddContactItem));
    await tester.pumpAndSettle();

    expect(find.byKey(UiKeys.addFriendIdInput), findsOneWidget,
        reason: 'the add-friend dialog must expose its ID input by key');

    final Finder submitButton = find.byKey(UiKeys.addFriendSubmitButton);
    expect(submitButton, findsOneWidget,
        reason: 'the add-friend dialog must expose its submit button by key');
    expect(
      tester.widget<FilledButton>(submitButton).onPressed,
      isNull,
      reason: 'submit stays disabled until the user enters a non-empty Tox ID',
    );

    await tester.enterText(
      find.byKey(UiKeys.addFriendIdInput),
      'A' * 64,
    );
    await tester.pump();

    expect(
      tester.widget<FilledButton>(submitButton).onPressed,
      isNotNull,
      reason:
          'typing a candidate Tox ID should enable the submit button before validation-on-submit',
    );
  });
}
