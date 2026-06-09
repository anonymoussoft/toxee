// Shared real-UI harness for the SettingsPage ACCOUNT-section gates
// (settings_account_*_real_ui_test.dart). NOT a `_test.dart` file — it holds no
// `testWidgets` and is only imported by the account-section test files, so the
// runner never picks it up as a suite.
//
// It packages exactly what every account gate needs to pump the PRODUCTION
// `SettingsPage` hermetically:
//   * `SettingsHarnessService` — a recording stub `FfiChatService` whose
//     `selfId` / `getSelfToxId` / `accountKey` resolve to a fixed 76-hex Tox
//     ID, so the page's account body renders and every Prefs/secure-storage
//     write keys under a single known account (mirrors `_ExportHarnessService`
//     in settings_export_chooser_real_ui_test.dart).
//   * `settingsApp` — a MaterialApp with the full l10n delegate set the fork
//     pages require, an optional NavigatorObserver, and a desktop-sized surface
//     (the export chooser / switch / logout dialogs take the `showDialog`
//     branch on the desktop test host).
//   * channel mocks for `flutter/platform` (captures `Clipboard.setData`,
//     answers `HapticFeedback`), `path_provider`, `file_picker`, and
//     `flutter_secure_storage` (an in-memory map so the real PBKDF2 password
//     write actually persists instead of being swallowed as a
//     MissingPluginException → `setPassword` false).
//   * `settle` — a bounded fixed-frame pump (the settings tree has an entrance
//     stagger + perpetual-ish async, so `pumpAndSettle` is unsafe).
//
// Mobile parity: SettingsPage + its account handlers are shared Dart in
// lib/ui/settings/ with no platform fork (only the export chooser CONTAINER
// forks: bottom sheet on mobile vs Dialog on desktop, rendering the SAME keyed
// tiles). These gates therefore cover the handlers on iOS/Android too. The only
// genuinely desktop-scoped leg is the native save panel inside `_exportAccount`
// / `_exportFullBackup` (guarded by `Platform.isWindows||Linux||MacOS`), which
// these gates do not reach (S43 territory).

library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tencent_cloud_chat_intl/localizations/tencent_cloud_chat_localizations.dart';
import 'package:tim2tox_dart/service/ffi_chat_service.dart';
import 'package:toxee/i18n/app_localizations.dart';

/// A 76-hex-char Tox address so account-scoped Prefs / secure-storage / display
/// logic behave like a real signed-in account. Same format the export-chooser
/// gate uses.
const String kSettingsToxId =
    'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF01234567';

/// A second distinct 76-hex Tox address for the account-switch gates (the
/// "other" local account the switch targets).
const String kSettingsOtherToxId =
    '1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF1234567890ABCDEF';

/// Recording stub satisfying the `FfiChatService` the real `SettingsPage`
/// requires, without booting the native FFI session. `selfId` / `getSelfToxId`
/// resolve to [kSettingsToxId] so `widget.service.accountKey` (used by the
/// export / password / logout / switch handlers) is the known account, and the
/// stream / profile mutations are no-ops. Mirrors `_ExportHarnessService`.
class SettingsHarnessService extends FfiChatService {
  SettingsHarnessService() : super();

  final StreamController<bool> _connection = StreamController<bool>.broadcast();

  @override
  bool get isConnected => true;

  @override
  Stream<bool> get connectionStatusStream => _connection.stream;

  @override
  String get selfId => kSettingsToxId;

  @override
  String? getSelfToxId() => kSettingsToxId;

  @override
  Future<void> updateSelfProfile({
    required String nickname,
    required String statusMessage,
  }) async {}

  @override
  Future<void> updateAvatar(String? avatarPath) async {}

  void disposeStub() => unawaited(_connection.close());
}

/// The full l10n delegate set the fork chat widgets + app pages read at build;
/// omit any and the page throws on its first localization lookup.
const List<LocalizationsDelegate<dynamic>> settingsLocalizationsDelegates = [
  AppLocalizations.delegate,
  TencentCloudChatLocalizations.delegate,
  GlobalMaterialLocalizations.delegate,
  GlobalWidgetsLocalizations.delegate,
  GlobalCupertinoLocalizations.delegate,
];

/// Wrap [child] in a MaterialApp with the required delegates. Pass
/// [navigatorObservers] to capture dialog route results.
Widget settingsApp(
  Widget child, {
  List<NavigatorObserver> navigatorObservers = const [],
}) {
  return MaterialApp(
    localizationsDelegates: settingsLocalizationsDelegates,
    supportedLocales: const [Locale('en')],
    navigatorObservers: navigatorObservers,
    home: Scaffold(body: child),
  );
}

/// Bounded settle: the real `SettingsPage` runs several `initState` Prefs reads
/// plus a `StaggeredListItem` entrance animation. `pumpAndSettle` is unsafe
/// (perpetual-ish animated descendants), so pump a fixed budget long enough to
/// flush the Prefs microtasks + the stagger.
Future<void> settleSettings(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Installs the channel mocks the SettingsPage account section touches and
/// returns a teardown closure. `tempRoot` feeds path_provider. The
/// `flutter/platform` handler captures Clipboard.setData into [clipboardLog] (a
/// list of the `text` values set) and answers everything else (HapticFeedback)
/// with null. `flutter_secure_storage` is backed by [secureStore] (an in-memory
/// map) so the REAL PBKDF2 password write actually persists.
///
/// Call the returned closure in `tearDown`.
class SettingsChannelMocks {
  SettingsChannelMocks._(this._teardown, this.clipboardLog, this.secureStore);

  final VoidCallback _teardown;

  /// Every `Clipboard.setData` text, in call order.
  final List<String> clipboardLog;

  /// In-memory backing for flutter_secure_storage (key -> value).
  final Map<String, String> secureStore;

  String? get lastClipboardText =>
      clipboardLog.isEmpty ? null : clipboardLog.last;

  void teardown() => _teardown();

  static SettingsChannelMocks install(Directory tempRoot) {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const platformChannel = MethodChannel(
      'flutter/platform',
      JSONMethodCodec(),
    );
    const pathProviderChannel = MethodChannel(
      'plugins.flutter.io/path_provider',
    );
    const filePickerChannel = MethodChannel(
      'miguelruivo.flutter.plugins.filepicker',
    );
    const secureStorageChannel = MethodChannel(
      'plugins.it_nomads.com/flutter_secure_storage',
    );

    final clipboardLog = <String>[];
    final secureStore = <String, String>{};

    messenger.setMockMethodCallHandler(platformChannel, (
      MethodCall call,
    ) async {
      if (call.method == 'Clipboard.setData') {
        // JSONMethodCodec delivers the arguments as a plain Map.
        final args = call.arguments;
        if (args is Map && args['text'] is String) {
          clipboardLog.add(args['text'] as String);
        }
        return null;
      }
      // HapticFeedback.* and everything else: inert.
      return null;
    });

    messenger.setMockMethodCallHandler(
      filePickerChannel,
      (MethodCall call) async => null,
    );

    messenger.setMockMethodCallHandler(pathProviderChannel, (
      MethodCall call,
    ) async {
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

    // Minimal in-memory flutter_secure_storage so the production PBKDF2 password
    // write (Prefs.setAccountPassword -> PasswordVerifier.setPassword) actually
    // persists hash+salt instead of being swallowed (a MissingPluginException
    // would make setPassword return false → the page shows "failed to set").
    messenger.setMockMethodCallHandler(secureStorageChannel, (
      MethodCall call,
    ) async {
      final args = (call.arguments as Map?) ?? const {};
      final key = args['key'] as String?;
      switch (call.method) {
        case 'write':
          if (key != null) secureStore[key] = args['value'] as String? ?? '';
          return null;
        case 'read':
          return key == null ? null : secureStore[key];
        case 'delete':
          if (key != null) secureStore.remove(key);
          return null;
        case 'containsKey':
          return key != null && secureStore.containsKey(key);
        case 'readAll':
          return Map<String, String>.from(secureStore);
        case 'deleteAll':
          secureStore.clear();
          return null;
        default:
          return null;
      }
    });

    void teardown() {
      messenger.setMockMethodCallHandler(platformChannel, null);
      messenger.setMockMethodCallHandler(pathProviderChannel, null);
      messenger.setMockMethodCallHandler(filePickerChannel, null);
      messenger.setMockMethodCallHandler(secureStorageChannel, null);
    }

    return SettingsChannelMocks._(teardown, clipboardLog, secureStore);
  }
}

/// Observer that attaches to the FIRST route pushed on top of the home route (a
/// dialog/popup) and reports the value it is popped with. Used by the export
/// chooser gate to read the exact 'tox' / 'zip' value the chooser routes back.
class FirstDialogResultObserver extends NavigatorObserver {
  FirstDialogResultObserver({required this.onRouteResult});

  final void Function(Object? value) onRouteResult;
  bool _captured = false;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (!_captured && previousRoute != null) {
      _captured = true;
      unawaited(route.popped.then(onRouteResult));
    }
    super.didPush(route, previousRoute);
  }
}
