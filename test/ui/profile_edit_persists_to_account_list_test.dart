// Regression test for S8 / roadmap L2-2: editing the self profile must mirror
// the new nickname + statusMessage into the `account_list` per-account ground
// truth, not only the global Prefs.
//
// The bug (fixed at lib/ui/settings/sidebar.dart:79-84): the showSelfProfile
// onSave closure wrote the global self_nickname / self_status_msg keys but did
// NOT write account_list. Because AccountService.initializeServiceForAccount
// re-derives the globals from the account_list row on every switch, the edit
// was silently rolled back on the next account switch.
//
// This drives the REAL path — showSelfProfile() builds ProfilePage with the
// real onSave closure; the test taps the edit toggle, edits the fields, and
// taps save so ProfilePage._handleSave -> onSave runs. Removing the
// Prefs.addAccount(...) mirror from the closure makes the account_list
// assertion fail. It is a widget test (test/ui/), not an FFI/host-bundle test:
// a recording FfiChatService stub absorbs updateSelfProfile (the only service
// call on the save path) and the account_list write is pure SharedPreferences,
// so no native library, no init/login, no skip-guard is needed.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/settings/sidebar.dart';
import 'package:toxee/ui/testing/ui_keys.dart';
import 'package:toxee/util/prefs.dart';

/// 76-char uppercase-hex synthetic Tox ID (public key + nospam + checksum
/// shape). No FFI is needed since the stub never loads a real profile.
const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

class _RecordingFfiChatService extends FfiChatService {
  _RecordingFfiChatService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  /// Records the last updateSelfProfile call so the test can prove the real
  /// onSave closure executed (vs. the account_list write coming from elsewhere).
  ({String nickname, String statusMessage})? lastProfileUpdate;

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  Future<void> updateSelfProfile(
      {required String nickname, required String statusMessage}) async {
    lastProfileUpdate = (nickname: nickname, statusMessage: statusMessage);
  }

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

Widget _harness(_RecordingFfiChatService service) {
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
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => showSelfProfile(
              context,
              service,
              service.connectionStatusStream,
              nickName: 'OriginalNick',
              statusMessage: 'origStatus',
            ),
            child: const Text('open profile'),
          ),
        ),
      ),
    ),
  );
}

/// Bounded settle: the profile QR section shows a perpetual
/// CircularProgressIndicator (profile_qr_section.dart), so pumpAndSettle never
/// settles. Pump a fixed number of frames instead — enough for the dialog
/// route transition, edit-mode rebuild, and the async onSave Prefs writes.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _RecordingFfiChatService service;
  late TestDefaultBinaryMessenger messenger;
  // SystemChannels.platform uses JSONMethodCodec; the mock must match or the
  // MaterialApp Title widget's SystemChrome call throws "Message corrupted".
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  setUp(() async {
    service = _RecordingFfiChatService();
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
        platformChannel, (MethodCall call) async => null);

    // Seed: one account whose account_list row + globals carry the BEFORE
    // state, and is the current account (so showSelfProfile's resolvedUserId
    // is this toxId).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.addAccount(
        toxId: _toxId, nickname: 'OriginalNick', statusMessage: 'origStatus');
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('OriginalNick');
    await Prefs.setStatusMessage('origStatus');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    service.disposeStub();
  });

  testWidgets('profile edit mirrors new nickname/status into account_list',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(_harness(service));
    await tester.pump();

    // Open the profile (real showSelfProfile → ProfilePage).
    await tester.tap(find.text('open profile'));
    await _settle(tester);

    // Enter edit mode so the editable fields render. Invoke the toggle's real
    // onPressed (== ProfilePage.onToggleEdit) directly: the dialog's layout
    // makes the IconButton center hit-test flaky, but firing the production
    // callback exercises the same setState path.
    expect(find.byKey(UiKeys.profileEditToggle), findsOneWidget,
        reason: 'editable profile must expose the edit toggle by key');
    tester
        .widget<IconButton>(find.byKey(UiKeys.profileEditToggle))
        .onPressed!
        .call();
    await _settle(tester);

    // Edit nickname + status.
    await tester.enterText(
        find.byKey(UiKeys.profileNicknameField), 'EditedNick');
    await tester.enterText(
        find.byKey(UiKeys.profileStatusField), 'EditedStatus');
    await tester.pump();

    // Save — fire the real FilledButton.onPressed (== ProfilePage._handleSave,
    // which runs the showSelfProfile onSave closure). Direct call for the same
    // hit-test reason; the save logic under test runs in full.
    final saveButton =
        tester.widget<FilledButton>(find.byKey(UiKeys.profileSaveButton));
    expect(saveButton.onPressed, isNotNull,
        reason: 'save button must be enabled after valid edits');
    saveButton.onPressed!.call();
    await _settle(tester);

    // Proof the real closure ran (not a reimplementation): the stub recorded
    // updateSelfProfile with the edited values.
    expect(service.lastProfileUpdate?.nickname, 'EditedNick',
        reason: 'the real onSave closure must call service.updateSelfProfile');

    // THE regression: account_list (per-account ground truth) reflects the
    // edit. Pre-fix this row stayed at OriginalNick and the edit was lost on
    // the next account switch.
    final row = await Prefs.getAccountByToxId(_toxId);
    expect(row?['nickname'], 'EditedNick',
        reason: 'onSave must mirror the new nickname into account_list');
    expect(row?['statusMessage'], 'EditedStatus',
        reason: 'onSave must mirror the new statusMessage into account_list');

    // Belt-and-suspenders: the global key is also updated (was true pre-fix
    // too, but guards a future drop of the setNickname call).
    expect(await Prefs.getNickname(), 'EditedNick');
  });
}
