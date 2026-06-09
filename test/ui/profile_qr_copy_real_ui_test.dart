// S103 — QR section copy (IMAGE): real-UI L1 gate.
//
// This file proves the REAL production handler `_copyQrImage`
// (profile_page.dart:287-298) invokes the `image_clipboard` plugin's
// MethodChannel with `copyImage(imagePath)`.
//
// WHY this is a real-UI gate (and HOW it differs from the synthetic probe and
// from a re-implementation):
//   - The existing probe (profile_anchor_keys_test.dart #3) pumps
//     `ProfileQrSection` with a SYNTHETIC `onCopy` counter — it never runs the
//     production handler.
//   - A weaker version of THIS test would hand-write the
//     `ImageClipboard().copyImage(...)` call inside the test `onCopy`; that only
//     exercises a COPY of the production code and would still pass if
//     `_copyQrImage` regressed. We do NOT do that.
//   - Instead we pump the REAL `ProfilePage` and reach into the REAL
//     `ProfileQrSection` that ProfilePage built (`profile_page.dart:483-495`),
//     whose `onCopy` IS the bound production method `_copyQrImage`. Invoking that
//     bound callback runs the production handler end-to-end against a mocked
//     `image_clipboard` channel. This is the same "fire the real bound callback"
//     pattern the repo already uses for `profileSaveButton`/`profileEditToggle`
//     (profile_edit_persists_to_account_list_test.dart) — a real production code
//     path, not a re-implementation.
//
// WHY we invoke the bound `onCopy` rather than tapping `profileQrCopyButton`:
// the copy button only mounts after ProfilePage's internal QR `FutureBuilder`
// resolves, which requires real canvas→PNG→temp-file image generation
// (`ContactQrCardGenerator.generateTempCard`) — non-deterministic in a widget
// test. The production wiring under test (`onCopy == _copyQrImage`, and the
// desktop `enableCopy` gate) is fully asserted without that I/O. The literal
// button hit-test + the OS image-pasteboard write stay L3 (a real run / the
// product-screenshot harness covers the rendered button).
//
// S103 honesty caveat (from the spec): the QR copy writes an IMAGE via the
// `image_clipboard` plugin, NOT text. A plain-text `Clipboard.setData` must NOT
// be written by this path. This gate asserts both the image-copy call and the
// absence of any text-clipboard write.
//
// Mobile-parity: `_copyQrImage` + `ProfileQrSection` are shared Dart
// (`lib/ui/profile_page.dart`, `lib/ui/profile/profile_qr_section.dart`) and the
// same `copyImage` MethodChannel call is made on every platform, so this L1 gate
// covers iOS/Android too. NOTE the production `enableCopy` gate
// (profile_page.dart:494) hides the QR copy BUTTON on Android/iOS/Linux; the
// handler itself is unchanged, and the desktop (macOS/Windows) copy affordance
// is what this gate exercises (the test host is desktop).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:toxee/i18n/app_localizations.dart';
import 'package:toxee/ui/profile_page.dart';
import 'package:toxee/ui/profile/profile_qr_section.dart';
import 'package:toxee/util/prefs.dart';
import 'package:path/path.dart' as p;

// Synthetic Tox ID (76 hex chars).
const String _toxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF012345';

// A path handed to the production `_copyQrImage` so we can assert the channel
// received exactly it. Not a real file — the handler only forwards the string.
const String _qrPath = '/tmp/profile_qr_copy_test.png';

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

// Bounded settle — never pumpAndSettle a ProfilePage (its QR FutureBuilder
// pumps a perpetual CircularProgressIndicator while image-gen runs).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 8; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestDefaultBinaryMessenger messenger;

  // `flutter/platform` (JSONMethodCodec): MaterialApp's SystemChrome title call,
  // and the channel any accidental `Clipboard.setData` (text) would ride.
  const platformChannel = MethodChannel('flutter/platform', JSONMethodCodec());

  // The `image_clipboard` plugin channel. Name + method confirmed from the
  // plugin source (image_clipboard_method_channel.dart):
  //   const MethodChannel('image_clipboard');
  //   methodChannel.invokeMethod('copyImage', {'imagePath': imagePath});
  const imageClipboardChannel = MethodChannel('image_clipboard');

  const pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

  late Directory tempRoot;

  final List<MethodCall> imageClipboardCalls = [];
  final List<String?> capturedTextClipboard = [];

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('profile_qr_copy_test_');
    messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    imageClipboardCalls.clear();
    capturedTextClipboard.clear();

    messenger.setMockMethodCallHandler(platformChannel, (call) async {
      if (call.method == 'Clipboard.setData') {
        final args = call.arguments as Map<Object?, Object?>?;
        capturedTextClipboard.add(args?['text'] as String?);
      }
      return null;
    });

    // Record the production `_copyQrImage` → `ImageClipboard().copyImage` call.
    // Without this mock the channel throws MissingPluginException in the sandbox.
    messenger.setMockMethodCallHandler(imageClipboardChannel, (call) async {
      imageClipboardCalls.add(call);
      return null; // copyImage returns void
    });

    messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
      switch (call.method) {
        case 'getApplicationSupportDirectory':
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

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    await Prefs.initialize(prefs);
    await Prefs.setCurrentAccountToxId(_toxId);
    await Prefs.setNickname('QR Test User');
    await Prefs.setStatusMessage('QR Test status');
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(platformChannel, null);
    messenger.setMockMethodCallHandler(imageClipboardChannel, null);
    messenger.setMockMethodCallHandler(pathProviderChannel, null);
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  testWidgets(
    'S103: the real ProfilePage wires QR copy to production _copyQrImage, which '
    'calls image_clipboard.copyImage (image, not text)',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      // Pump the REAL self-profile page (isEditable → the editable self profile
      // that renders the QR section with the copy affordance).
      await tester.pumpWidget(
        _app(
          const ProfilePage(
            userId: _toxId,
            nickName: 'QR Test User',
            statusMessage: 'QR Test status',
            isEditable: true,
          ),
        ),
      );
      await _settle(tester);

      // The REAL ProfileQrSection that ProfilePage built (ProfileLayout always
      // invokes its qrSectionBuilder). Its `onCopy` is the bound production
      // `_copyQrImage`, and `enableCopy` reflects the production desktop gate.
      final section = tester.widget<ProfileQrSection>(
        find.byType(ProfileQrSection),
      );

      // S103-A1 (production wiring): ProfileQrSection.enableCopy must mirror the
      // production platform gate (profile_page.dart:494 — copy is OFF on
      // Android/iOS/Linux, ON on macOS/Windows). Asserting the exact gate keeps
      // this host-portable (incl. Linux CI) while still catching a regression
      // that flips the gate on the current host.
      final expectedEnableCopy =
          !(Platform.isAndroid || Platform.isIOS || Platform.isLinux);
      expect(
        section.enableCopy,
        expectedEnableCopy,
        reason:
            'S103-A1: ProfileQrSection.enableCopy must match the production '
            'platform gate (profile_page.dart:494)',
      );

      // Drive the REAL production handler: ProfilePage wired this `onCopy` to its
      // private `_copyQrImage`. Invoking it runs the production copy path
      // end-to-end (the same call `() => onCopy(qrPath)` the keyed button makes).
      section.onCopy(_qrPath);
      await _settle(tester);

      // S103-A2 (primary): the production handler hit image_clipboard.copyImage
      // with the path it was given.
      expect(
        imageClipboardCalls,
        isNotEmpty,
        reason: 'S103-A2: production _copyQrImage must call image_clipboard',
      );
      final imageCall = imageClipboardCalls.last;
      expect(imageCall.method, 'copyImage',
          reason: 'S103-A2: channel method must be copyImage');
      final callArgs = imageCall.arguments as Map<Object?, Object?>?;
      expect(
        callArgs?['imagePath'],
        _qrPath,
        reason: 'S103-A2: copyImage must receive the path passed to _copyQrImage',
      );

      // S103 honesty caveat: the QR copy writes an IMAGE, not text. No
      // Clipboard.setData (text) must be written on this path. A future refactor
      // that switched to text copy would be caught here.
      expect(
        capturedTextClipboard,
        isEmpty,
        reason: 'S103: QR copy must NOT write text via Clipboard.setData',
      );

      // S103-A3: the success snackbar fired from the production handler
      // (AppSnackBar.showSuccess, profile_page.dart:292).
      expect(
        find.text('ID copied to clipboard'),
        findsOneWidget,
        reason: 'S103-A3: production _copyQrImage shows the success snackbar',
      );
    },
  );
}
