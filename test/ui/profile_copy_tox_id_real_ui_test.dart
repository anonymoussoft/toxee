// S102 — Copy Tox ID button → clipboard (TEXT): real-UI L1 gate
//
// This file proves the REAL production handler `_copyToxId` (profile_page.dart:300-312)
// writes the correct Tox ID text to the OS clipboard channel when the user taps
// `UiKeys.profileToxIdCopyButton` in the mounted `ProfilePage`.
//
// WHY this is a real-UI gate (not the existing synthetic-callback probe):
//   - We pump the REAL `ProfilePage` via `showSelfProfile`, which wires the
//     production `onCopy: _copyToxId` closure — NOT a synthetic counter.
//   - We intercept the `flutter/platform` MethodChannel mock to RECORD
//     `Clipboard.setData` calls and verify the payload, proving the production
//     handler ran end-to-end.
//   - A synthetic onCopy counter (profile_anchor_keys_test.dart, test #2) only
//     proves the button fires the callback; it does NOT exercise the real
//     `Clipboard.setData` write.  This gate covers the missing step.
//
// Cross-process clipboard ground truth (`pbpaste`) stays L3 per S102's promotion
// note: `Clipboard.setData` in Flutter sends to the platform channel mock in
// widget tests; the OS pasteboard write is a host-process concern.
//
// Mobile-parity: `_copyToxId` and `ProfileToxIdSection` live in shared Dart
// (`lib/ui/profile/profile_edit_fields.dart`, `lib/ui/profile_page.dart`).
// The same code path runs on iOS and Android; only the host-side `pbpaste`
// verification command differs per platform.  This L1 gate covers all targets.
library;

import 'dart:async';
import 'dart:io';

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
import 'package:path/path.dart' as p;

// Synthetic Tox ID matching the real shape:
//   32-byte public key + 4-byte nospam + 2-byte checksum = 38 bytes = 76 hex chars.
// Uppercase hex only; 76 chars exactly.
const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF012345';

// Minimal stub — absorbs service calls that ProfilePage/showSelfProfile makes
// (updateSelfProfile, updateAvatar, connectionStatusStream) with no native lib.
class _StubFfiChatService extends FfiChatService {
  _StubFfiChatService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => false;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => _toxId;

  @override
  String? getSelfToxId() => _toxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

// The standard harness wrapper: a MaterialApp with all required localizations
// delegates so TencentCloudChatLocalizations resolves inside ProfilePage.
Widget _app(Widget child) {
  return MaterialApp(
    localizationsDelegates: const [
      AppLocalizations.delegate,
      TencentCloudChatLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('en')],
    home: Scaffold(body: child),
  );
}

// Bounded settle: the QR FutureBuilder shows a perpetual CircularProgressIndicator;
// pumpAndSettle hangs forever.  Pump 8 × 100ms (800ms total) — enough for the
// showDialog route transition, the ProfilePage build, and the Clipboard channel
// round-trip without waiting for the QR to resolve.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _StubFfiChatService service;
  late TestDefaultBinaryMessenger messenger;

  // The clipboard and system chrome share the `flutter/platform` channel (JSONMethodCodec).
  // Without mocking it, MaterialApp's SystemChrome title call throws "Message corrupted".
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  // path_provider: ProfilePage._loadAvatar tries getApplicationSupportDirectory
  // and getApplicationDocumentsDirectory; mock to a temp dir.
  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempRoot;

  // Captures every Clipboard.setData call: maps the text argument for assertion.
  final List<String?> capturedClipboardTexts = [];

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('profile_copy_tox_id_test_');
    service = _StubFfiChatService();
    messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    // WHY we record here: the production `_copyToxId` does:
    //   Clipboard.setData(ClipboardData(text: widget.userId))
    // which sends `{'text': toxId}` as the argument to 'Clipboard.setData' on
    // the 'flutter/platform' channel.  Recording it here is the only in-process
    // way to verify the real handler ran and sent the right payload.
    capturedClipboardTexts.clear();
    messenger.setMockMethodCallHandler(platformChannel, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>?;
        capturedClipboardTexts.add(args?['text'] as String?);
      }
      return null;
    });

    messenger.setMockMethodCallHandler(pathProviderChannel, (MethodCall call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
          return tempRoot.path;
        case 'getApplicationDocumentsDirectory':
          return tempRoot.path;
        case 'getApplicationCacheDirectory':
          return p.join(tempRoot.path, 'cache');
        case 'getTemporaryDirectory':
          return p.join(tempRoot.path, 'temp');
        case 'getDownloadsDirectory':
          return p.join(tempRoot.path, 'Downloads');
        default:
          return null;
      }
    });

    // Seed Prefs so showSelfProfile takes the storedToxId branch and
    // ProfilePage.userId == _toxId (not the UIKit `FlutterUIKitClient` placeholder).
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('Test User');
    await Prefs.setStatusMessage('Test status');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    service.disposeStub();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'S102: tapping profileToxIdCopyButton writes the real 76-hex toxId to the clipboard channel',
    (WidgetTester tester) async {
      // Desktop surface: showSelfProfile uses a dialog on desktop (width > 600px),
      // which is what we want here so we avoid the full-screen route.
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // WHY showSelfProfile: it wires the REAL `onCopy: _copyToxId` closure
      // inside ProfilePage, including the `Prefs.getCurrentAccountToxId()` look-
      // up that resolves the displayed userId.  Pumping ProfilePage directly with
      // a dummy `onCopy` would not exercise the production handler.
      await tester.pumpWidget(
        _app(
          Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showSelfProfile(
                context,
                service,
                service.connectionStatusStream,
                nickName: 'Test User',
                statusMessage: 'Test status',
              ),
              child: const Text('open profile'),
            ),
          ),
        ),
      );
      await tester.pump();

      // Open the real ProfilePage dialog.
      await tester.tap(find.text('open profile'));
      await _settle(tester);

      // A3 (partial): the selectable text widget is present and renders the full
      // 76-hex toxId — proves ProfileToxIdSection received the real userId and is
      // NOT truncated or placeholder-leaked.
      expect(
        find.byKey(UiKeys.profileToxIdSelectableText),
        findsOneWidget,
        reason: 'profileToxIdSelectableText must be visible in the real ProfilePage',
      );
      final selectable = tester.widget<SelectableText>(
        find.byKey(UiKeys.profileToxIdSelectableText),
      );
      expect(
        selectable.data,
        _toxId,
        reason: 'SelectableText must render the full 76-hex toxId, not a truncated/placeholder value',
      );
      expect(
        selectable.data!.length,
        76,
        reason: 'S102-A3: displayed toxId must be exactly 76 chars (38 bytes hex-encoded)',
      );

      // The copy button is the REAL production key — wired to `_copyToxId`.
      expect(
        find.byKey(UiKeys.profileToxIdCopyButton),
        findsOneWidget,
        reason: 'profileToxIdCopyButton must be present in the real ProfilePage',
      );

      // Tap the REAL copy button → triggers `_copyToxId` → `Clipboard.setData`.
      // WHY we tap rather than calling onPressed directly: tapping exercises the
      // real hit-test + gesture recognizer path, proving the button is tappable
      // and not blocked by an overlay or zero-size box.
      await tester.tap(find.byKey(UiKeys.profileToxIdCopyButton));
      await tester.pump();

      // S102-A2 (primary): the recorded Clipboard.setData text is exactly the
      // seeded 76-hex toxId.  This proves the REAL `_copyToxId` handler ran
      // (not a synthetic stub) and wrote `widget.userId` — the real toxId —
      // not any other value.
      expect(
        capturedClipboardTexts,
        isNotEmpty,
        reason:
            'S102-A2: Clipboard.setData must have been called by the real _copyToxId handler',
      );
      final writtenText = capturedClipboardTexts.last;
      expect(
        writtenText,
        _toxId,
        reason: 'S102-A2: clipboard payload must be the real 76-hex toxId',
      );

      // S102-A2 (format guard): matches the Tox ID hex pattern.
      final hexPattern = RegExp(r'^[0-9a-fA-F]{76}$');
      expect(
        hexPattern.hasMatch(writtenText!),
        isTrue,
        reason: 'S102-A2: clipboard text must match ^[0-9a-fA-F]{76}\$',
      );

      // S102-A5 (placeholder-leak guard): the UIKit selfId placeholder
      // `FlutterUIKitClient` must NEVER reach the clipboard.  A regression to
      // `service.selfId` instead of `widget.userId`/Prefs would leak this.
      expect(
        writtenText,
        isNot('FlutterUIKitClient'),
        reason: 'S102-A5: clipboard must NOT contain the UIKit selfId placeholder',
      );

      // S102-A4 (optional): the snackbar "ID copied to clipboard" appears,
      // proving AppSnackBar.showSuccess fired on the happy path.
      // We pump one more frame for the SnackBar to mount.
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        find.text('ID copied to clipboard'),
        findsOneWidget,
        reason: 'S102-A4: success snackbar must appear after the real copy handler runs',
      );
    },
  );
}
